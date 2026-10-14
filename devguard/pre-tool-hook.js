#!/usr/bin/env node
/**
 * PromptShield PreToolUse Hook
 * Validates user prompts only; passes through Read/Write/git/system commands.
 * Always prints valid JSON to stdout: {"verdict":"PASS"} or {"verdict":"BLOCK",...}
 */
const fs    = require("fs");
const path  = require("path");
const os    = require("os");
const http  = require("http");
const https = require("https");

const GLOBAL_CONFIG = path.join(os.homedir(), ".devguard", "config", "config.json");
const PS_DIR        = path.join(process.cwd(), ".promptshield");
const CLAUDE_MD     = path.join(PS_DIR, "CLAUDE.md");
const PS_CONFIG     = path.join(PS_DIR, "config.json");

function cfg() {
  let global = {}, project = {};
  try { global  = JSON.parse(fs.readFileSync(GLOBAL_CONFIG, "utf8")); } catch {}
  try { project = JSON.parse(fs.readFileSync(PS_CONFIG,     "utf8")); } catch {}
  return { ...global, ...project };
}

function readCLAUDEmd() {
  try { return fs.readFileSync(CLAUDE_MD, "utf8").trim(); } catch {}
  try { return fs.readFileSync(path.join(os.homedir(), ".devguard", "CLAUDE.md"), "utf8").trim(); } catch {}
  return null;
}

const readStdin = () => new Promise(r => {
  let d = "";
  process.stdin.setEncoding("utf8").on("data", c => d += c)
    .on("end", () => { try { r(JSON.parse(d)); } catch { r(null); } });
  setTimeout(() => r(null), 2000);
});

const BLOCKS = [
  { re: /while\s+you'?re\s+(there|at it)/i,            rule: "L1-007", msg: "Scope creep — one change per prompt" },
  { re: /skip\s+(the\s+)?(deliberation|gate\s*[12])/i, rule: "L2-K002", msg: "Gate bypass — deliberation and gates are mandatory" },
  { re: /bypass\s+gate|override\s+gate/i,               rule: "L2-S005", msg: "Gate bypass — absolute rule" },
  { re: /merge\s+(it\s+)?myself|auto.merge/i,           rule: "L2-I009", msg: "Self-merge — PRs always need a reviewer" },
  { re: /deploy\s+to\s+prod(?!uction\s+deploy)/i,       rule: "L2-S005", msg: "Direct prod deploy without /ship is blocked" },
  { re: /and\s+anything\s+else|fix\s+all\s+the\s+issues/i, rule: "L1-007", msg: "Unbounded scope — one verifiable outcome per prompt" },
  { re: /change\s+the\s+test|modify\s+the\s+assertion/i, rule: "L3-BF004", msg: "Test manipulation — fix code not the test" },
];
const WARNS = [
  { re: /\brefactor\b|\bclean\s+up\b/i,       rule: "L2-BF003", msg: "Refactor in /bugfix? Needs a separate /enhance story" },
  { re: /make\s+it\s+better(?!\s+by)/i,        rule: "L1-008",  msg: "Vague outcome — specify the measurable improvement" },
];

function localValidate(prompt) {
  for (const b of BLOCKS) { if (b.re.test(prompt)) return { verdict: "BLOCK", rule: b.rule, msg: b.msg }; }
  for (const w of WARNS)  { if (w.re.test(prompt)) return { verdict: "WARN",  rule: w.rule, msg: w.msg }; }
  return { verdict: "PASS" };
}

function request(base, token, method, p, body) {
  return new Promise(resolve => {
    if (!base || !token) { resolve(null); return; }
    const isHttps = base.startsWith("https");
    const lib = isHttps ? https : http;
    const data = body ? JSON.stringify(body) : null;
    const u = new URL(p, base);
    const req = lib.request({
      hostname: u.hostname, port: u.port || (isHttps ? 443 : 80), path: u.pathname, method,
      headers: { "content-type": "application/json", "authorization": `Bearer ${token}`, ...(data ? { "content-length": Buffer.byteLength(data) } : {}) },
    }, res => { let d = ""; res.on("data", c => d += c); res.on("end", () => { try { resolve(JSON.parse(d)); } catch { resolve(null); } }); });
    req.on("error", () => resolve(null));
    req.setTimeout(4000, () => { req.destroy(); resolve(null); });
    if (data) req.write(data);
    req.end();
  });
}

async function rewriteViaGateway(prompt, claudeMd) {
  const c = cfg();
  if (!c.gatewayUrl || !c.developerToken) return null;
  return request(c.gatewayUrl, c.developerToken, "POST", "/api/v1/devguard/rewrite", { prompt, claudeMd });
}

async function rewriteLocalMax(prompt, claudeMd) {
  const apiKey = process.env.ANTHROPIC_API_KEY || cfg().anthropicApiKey || "";
  if (!apiKey) return null;
  const system = `You are PromptShield DevGuard. Improve this prompt into the best possible ITM slash command.
Context:\n${claudeMd || "No CLAUDE.md found."}\nReturn ONLY raw JSON: {"rewritten":"...","changes":"...","token_saving":"..."}`;
  return new Promise(resolve => {
    const body = JSON.stringify({ model: "claude-haiku-4-5-20251001", max_tokens: 300, system, messages: [{ role: "user", content: `Rewrite:\n\n${prompt}` }] });
    const req = https.request({
      hostname: "api.anthropic.com", path: "/v1/messages", method: "POST",
      headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json", "content-length": Buffer.byteLength(body) },
    }, res => { let d = ""; res.on("data", c => d += c); res.on("end", () => { try { resolve(JSON.parse(JSON.parse(d).content?.[0]?.text || "{}")); } catch { resolve(null); } }); });
    req.on("error", () => resolve(null));
    req.setTimeout(5000, () => { req.destroy(); resolve(null); });
    req.write(body);
    req.end();
  });
}

function printBlock(rule, msg, rewritten) {
  process.stderr.write([
    "", "┌─ PromptShield BLOCK ──────────────────────────────────────────",
    `│ Rule:    ${rule}`, `│ Problem: ${msg}`, "│",
    ...(rewritten ? ["│ ✓ Corrected prompt:", ...rewritten.split("\n").map(l => `│   ${l}`)] : []),
    "└────────────────────────────────────────────────────────────────", "",
  ].join("\n") + "\n");
}

function printRewrite(rewritten, changes, saving) {
  process.stderr.write([
    "", "┌─ PromptShield IMPROVED ────────────────────────────────────────",
    `│ Change:  ${changes}`, saving ? `│ Saving:  ~${saving} tokens` : null, "│",
    "│ Use this prompt:", ...rewritten.split("\n").map(l => `│   ${l}`),
    "└────────────────────────────────────────────────────────────────", "",
  ].filter(Boolean).join("\n") + "\n");
}

function emitVerdict(obj) {
  process.stdout.write(JSON.stringify(obj));
}

function passAndExit() {
  emitVerdict({ verdict: "PASS" });
  process.exit(0);
}

function looksLikeUserPrompt(text) {
  const t = String(text || "").trim();
  if (!t) return false;
  if (t.startsWith("/")) return true;
  if (/^(git|npm|npx|yarn|pnpm|pip|python\d*|node|cd|ls|cat|head|tail|grep|find|curl|wget|docker|kubectl|make|cargo|go|pytest|uvicorn|bash|sh|echo|export|env|mkdir|rm|cp|mv|touch|chmod|sudo|which|whoami|pwd|open|xargs|sed|awk)\b/i.test(t)) {
    return false;
  }
  if (/^[~.]/.test(t)) return false;
  return /[a-zA-Z]/.test(t) && (/\s/.test(t) || t.length > 48);
}

async function run() {
  const ctx = await readStdin();
  const tool = ctx?.tool_name || "";

  // 1–2: Non-Bash tools (Read, Write, MCP, etc.) — pass through
  if (tool !== "Bash") {
    passAndExit();
    return;
  }

  const command = ctx?.tool_input?.command || ctx?.tool_input?.prompt || "";

  // 3–4: Bash system/git/file ops — pass through
  if (!looksLikeUserPrompt(command)) {
    passAndExit();
    return;
  }

  // 5: Full DevGuard validation for user prompts only
  const sessionFlag = path.join(os.tmpdir(), `.ps-session-${process.pid}`);
  if (!fs.existsSync(sessionFlag)) {
    try {
      fs.writeFileSync(sessionFlag, "");
      const startScript = path.join(os.homedir(), ".devguard", "bin", "session-start.js");
      if (fs.existsSync(startScript)) {
        const { spawnSync } = require("child_process");
        spawnSync("node", [startScript], { stdio: ["inherit", "inherit", "inherit"], timeout: 120000, cwd: process.cwd() });
      }
    } catch { /* fail open */ }
  }

  const local = localValidate(command);

  if (local.verdict === "BLOCK") {
    try {
      const claudeMd = readCLAUDEmd();
      const rw = await rewriteViaGateway(command, claudeMd) || await rewriteLocalMax(command, claudeMd);
      printBlock(local.rule, local.msg, rw?.rewritten || null);
    } catch { /* fail open on rewrite errors */ }
    emitVerdict({ verdict: "BLOCK", rule: local.rule, msg: local.msg });
    process.exit(0);
    return;
  }

  if (local.verdict === "WARN") {
    process.stderr.write(`\n⚠ PromptShield [${local.rule}]: ${local.msg}\n`);
  }

  if (command.length < 80 && !command.startsWith("/")) {
    try {
      const claudeMd = readCLAUDEmd();
      const rw = await rewriteViaGateway(command, claudeMd) || await rewriteLocalMax(command, claudeMd);
      if (rw?.rewritten && rw.rewritten !== command) {
        printRewrite(rw.rewritten, rw.changes || "", rw.token_saving || "");
      }
    } catch { /* fail open */ }
  }

  passAndExit();
}

// 6: Fail open — never crash or emit invalid JSON
try {
  run().catch(() => passAndExit());
} catch {
  passAndExit();
}
