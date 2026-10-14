#!/usr/bin/env bash
# PromptShield — One-line installer (Mac + Linux + Windows WSL/Git Bash)
# curl -fsSL https://promptshield-nwhb.onrender.com/install.sh | bash -s -- --device-id DID-XXXX-XXXX-XXXX --mode max
# Or with args:
# curl -fsSL https://promptshield-nwhb.onrender.com/install.sh | bash -s -- --device-id DID-XXXX-XXXX-XXXX --mode max -s -- --device-id DID-XXXX-XXXX --name "My MacBook"

set -euo pipefail

REPO="arcstream-ext/promptshield"
GATEWAY_URL="https://promptshield-nwhb.onrender.com"
PAGES_URL="https://arcstream-ext.github.io/promptshield"
VERSION="1.0.0"
INSTALL_DIR="$HOME/.devguard"
BIN_DIR="$HOME/.local/bin"
RAW="https://raw.githubusercontent.com/${REPO}/main"

# ── Colours (disabled on Windows cmd) ────────────────────────────────────────
if [[ "${TERM:-}" == "dumb" ]] || [[ "${OS:-}" == "Windows_NT" && -z "${MSYSTEM:-}" ]]; then
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
else
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
fi

step(){ echo -e "${BOLD}${BLUE}→${NC} $1"; }
ok(){   echo -e "${GREEN}✓${NC} $1"; }
warn(){ echo -e "${YELLOW}⚠${NC} $1"; }
die(){  echo -e "${RED}✕ ERROR:${NC} $1"; exit 1; }
ask(){  echo -e "${YELLOW}?${NC} $1"; }

# ── Detect OS and platform ────────────────────────────────────────────────────
detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then echo "mac"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then echo "linux"
  elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || -n "${MSYSTEM:-}" ]]; then echo "windows-bash"
  elif [[ "${OS:-}" == "Windows_NT" ]]; then echo "windows"
  else echo "linux"
  fi
}
OS_TYPE=$(detect_os)

# Windows PATH for Node/npm installed via winget or nvm-windows
if [[ "$OS_TYPE" == "windows-bash" ]]; then
  export PATH="$PATH:/c/Program Files/nodejs:/c/Users/$USERNAME/AppData/Roaming/npm"
fi

# ── Parse arguments ───────────────────────────────────────────────────────────
DEVICE_ID=""; NAME=""; MODE="api"; SKIP_CURSOR=false; SKIP_CLAUDE=false; SILENT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --device-id)   DEVICE_ID="$2";    shift 2 ;;
    --name)        NAME="$2";         shift 2 ;;
    --mode)        MODE="$2";         shift 2 ;;  # api | max
    --no-cursor)   SKIP_CURSOR=true;  shift ;;
    --no-claude)   SKIP_CLAUDE=true;  shift ;;
    --silent)      SILENT=true;       shift ;;
    # Legacy token support
    --token)       DEVICE_ID="$2";    shift 2 ;;
    *) shift ;;
  esac
done

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${CYAN}"
echo "  ⬡  PromptShield — AI Developer Governance"
echo "  v${VERSION} · ${OS_TYPE}"
echo -e "${NC}"

# ── Check dependencies ────────────────────────────────────────────────────────
step "Checking dependencies..."

check_cmd() {
  command -v "$1" >/dev/null 2>&1
}

if ! check_cmd curl && ! check_cmd wget; then
  die "curl or wget required. Install curl: https://curl.se/download.html"
fi
if ! check_cmd node; then
  echo ""
  echo -e "${RED}Node.js not found.${NC} Install it first:"
  echo ""
  if [[ "$OS_TYPE" == "mac" ]]; then
    echo "  brew install node"
    echo "  — or — download from https://nodejs.org"
  elif [[ "$OS_TYPE" == "windows-bash" || "$OS_TYPE" == "windows" ]]; then
    echo "  winget install OpenJS.NodeJS.LTS"
    echo "  — or — download from https://nodejs.org"
    echo "  Then restart your terminal."
  else
    echo "  sudo apt install nodejs npm   (Ubuntu/Debian)"
    echo "  sudo dnf install nodejs       (Fedora)"
    echo "  — or — https://nodejs.org"
  fi
  echo ""
  die "Install Node.js ≥18 then re-run this installer"
fi

node -e "process.exit(parseInt(process.version.slice(1))<18?1:0)" 2>/dev/null \
  || die "Node.js ≥18 required. Current: $(node --version). Update at https://nodejs.org"

check_cmd git || warn "git not found — some features may not work"
ok "Dependencies OK (Node $(node --version))"

# ── Collect device info ───────────────────────────────────────────────────────
if [[ -z "$DEVICE_ID" ]]; then
  echo ""
  ask "Paste your Device ID (from ${PAGES_URL}/mode-b → My Devices → Add Device):"
  ask "It looks like: DID-XXXX-XXXX-XXXX"
  read -r DEVICE_ID
  [[ -z "$DEVICE_ID" ]] && die "Device ID required. Generate one at ${PAGES_URL}/mode-b"
fi

if [[ -z "$NAME" ]]; then
  # Auto-detect device name
  if [[ "$OS_TYPE" == "mac" ]]; then
    DEFAULT_NAME=$(scutil --get ComputerName 2>/dev/null || hostname)
  elif [[ "$OS_TYPE" == "windows-bash" ]]; then
    DEFAULT_NAME="${COMPUTERNAME:-$(hostname)}"
  else
    DEFAULT_NAME=$(hostname)
  fi
  ask "Device name [${DEFAULT_NAME}] (press Enter to use):"
  read -r NAME
  NAME="${NAME:-$DEFAULT_NAME}"
fi

echo ""
ok "Device: ${NAME} (${OS_TYPE})"
ok "Device ID: ${DEVICE_ID}"

# ── Install PromptShield core ─────────────────────────────────────────────────
step "Installing PromptShield core..."
mkdir -p "${INSTALL_DIR}"/{bin,rules,config} "${BIN_DIR}"

# Write DevGuard scripts (embedded — no GitHub download required)
cat > "${INSTALL_DIR}/bin/pre-tool-hook.js" << 'HEREDOC'
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
HEREDOC
chmod +x "${INSTALL_DIR}/bin/pre-tool-hook.js"

cat > "${INSTALL_DIR}/bin/usage-reporter.js" << 'HEREDOC'
#!/usr/bin/env node
// PromptShield PostToolUse / UserPromptSubmit Hook — reports token usage to gateway
const fs = require("fs"), path = require("path"), os = require("os"), https = require("https");
const CONFIG = path.join(os.homedir(), ".devguard", "config", "config.json");
const QUEUE  = path.join(os.homedir(), ".devguard", "queue.jsonl");
const cfg = () => { try { return JSON.parse(fs.readFileSync(CONFIG, "utf8")); } catch { return {}; } };
const readStdin = () => new Promise(r => { let d=""; process.stdin.setEncoding("utf8").on("data",c=>d+=c).on("end",()=>{try{r(JSON.parse(d))}catch{r(null)}}); setTimeout(()=>r(null),2000); });

function send(url, token, body) {
  return new Promise(r => {
    const u = new URL(url), data = JSON.stringify(body);
    const isHttps = u.protocol === "https:";
    const lib = isHttps ? require("https") : require("http");
    const req = lib.request({
      hostname:u.hostname, port:u.port||(isHttps?443:80), path:u.pathname, method:"POST",
      headers:{"Content-Type":"application/json","Content-Length":Buffer.byteLength(data),"Authorization":`Bearer ${token}`}
    }, res => r(res.statusCode < 300));
    req.on("error",()=>r(false));
    req.setTimeout(3000,()=>{req.destroy();r(false)});
    req.write(data); req.end();
  });
}

function tokensFromToolCall(ctx) {
  const usage = ctx?.usage || ctx?.response?.usage || {};
  const inputChars = JSON.stringify(ctx?.tool_input || {}).length;
  const outputChars = String(ctx?.tool_response || "").length;
  const estimatedInput = Math.ceil(inputChars / 4);
  const estimatedOutput = Math.ceil(outputChars / 4);
  const inp = usage.input_tokens || estimatedInput;
  const out = usage.output_tokens || estimatedOutput;
  const tokenSource = usage.input_tokens ? "exact" : "estimated";
  return { inp, out, tokenSource };
}

function tokensFromUserPrompt(ctx) {
  const usage = ctx?.usage || ctx?.response?.usage || {};
  const promptChars = String(ctx?.prompt || ctx?.message || "").length;
  const estimatedPromptTokens = Math.ceil(promptChars / 4);
  const inp = usage.input_tokens || estimatedPromptTokens;
  const out = usage.output_tokens || 0;
  const tokenSource = usage.input_tokens ? "exact" : "estimated";
  return { inp, out, tokenSource };
}

function resolveTokens(ctx) {
  const event = ctx?.hook_event_name || "";
  if (event === "UserPromptSubmit") {
    return tokensFromUserPrompt(ctx);
  }
  return tokensFromToolCall(ctx);
}

(async () => {
  const c = cfg();
  if (!c.developerToken || !c.gatewayUrl) return;
  const ctx = await readStdin();
  if (!ctx) return;

  const { inp, out, tokenSource } = resolveTokens(ctx);
  if (inp + out === 0) return;

  const event = {
    ts: new Date().toISOString(),
    developer: c.developerName,
    token: c.developerToken,
    tool: ctx?.tool_name || (ctx?.hook_event_name === "UserPromptSubmit" ? "prompt" : "chat"),
    inputTokens: inp,
    outputTokens: out,
    totalTokens: inp + out,
    costUsd: inp * 0.000003 + out * 0.000015,
    model: ctx?.model || ctx?.response?.model || "claude-sonnet-4-6",
    devguardVerdict: ctx?.devguard_verdict || "PASS",
    register: true,
    tokenSource,
  };
  const ok = await send(`${c.gatewayUrl}/api/v1/usage`, c.developerToken, event);
  if (!ok) { try { fs.appendFileSync(QUEUE, JSON.stringify(event)+"\n"); } catch {} }
})().catch(()=>{});
HEREDOC
chmod +x "${INSTALL_DIR}/bin/usage-reporter.js"

cat > "${INSTALL_DIR}/bin/claude-md-sync.js" << 'HEREDOC'
#!/usr/bin/env node
/**
 * PromptShield CLAUDE.md Sync — Gap 2
 *
 * Pulls the latest CLAUDE.md from the gateway and writes it locally.
 * Runs on: install, team-claude login, and periodically via cron.
 *
 * This ensures every MacBook always has the current CLAUDE.md
 * without any manual steps from the developer.
 */
const fs    = require("fs");
const path  = require("path");
const os    = require("os");
const http  = require("http");
const https = require("https");

const CONFIG      = path.join(os.homedir(), ".devguard", "config", "config.json");
const LOCAL_CACHE = path.join(os.homedir(), ".devguard", "CLAUDE.md"); // global fallback

function cfg() {
  try { return JSON.parse(fs.readFileSync(CONFIG, "utf8")); }
  catch { return {}; }
}

function fetchFromGateway(gatewayUrl, token) {
  return new Promise((resolve) => {
    const u = new URL("/api/v1/claude-md", gatewayUrl);
    const isHttps = u.protocol === "https:";
    const lib = isHttps ? https : http;
    const opts = {
      hostname: u.hostname,
      port: u.port || (isHttps ? 443 : 80),
      path: u.pathname,
      method: "GET",
      headers: { "authorization": `Bearer ${token}` },
    };
    const req = lib.request(opts, res => {
      let d = "";
      res.on("data", c => d += c);
      res.on("end", () => {
        try {
          const parsed = JSON.parse(d);
          resolve(parsed.content || null);
        } catch { resolve(null); }
      });
    });
    req.on("error", () => resolve(null));
    req.setTimeout(5000, () => { req.destroy(); resolve(null); });
    req.end();
  });
}

async function sync(silent = false) {
  const c = cfg();
  if (!c.gatewayUrl || !c.developerToken) {
    if (!silent) console.log("⚠ No gateway configured — skipping CLAUDE.md sync");
    return false;
  }

  const content = await fetchFromGateway(c.gatewayUrl, c.developerToken);
  if (!content) {
    if (!silent) console.log("⚠ Could not fetch CLAUDE.md from gateway");
    return false;
  }

  // Write to ~/.devguard/CLAUDE.md (global fallback for all projects)
  fs.mkdirSync(path.dirname(LOCAL_CACHE), { recursive: true });
  fs.writeFileSync(LOCAL_CACHE, content, "utf8");

  // Write to .promptshield/CLAUDE.md in current project
  const psDir = path.join(process.cwd(), ".promptshield");
  if (fs.existsSync(psDir)) {
    const projectClaude = path.join(psDir, "CLAUDE.md");
    fs.writeFileSync(projectClaude, content, "utf8");
    if (!silent) console.log(`✓ CLAUDE.md synced → ${projectClaude}`);
  }

  if (!silent) console.log(`✓ CLAUDE.md synced → ${LOCAL_CACHE}`);
  return true;
}

// Export for use in other scripts
module.exports = { sync };

// Run directly
if (require.main === module) {
  sync(false).then(ok => process.exit(ok ? 0 : 1));
}
HEREDOC
chmod +x "${INSTALL_DIR}/bin/claude-md-sync.js"

cat > "${INSTALL_DIR}/bin/review-logger.js" << 'HEREDOC'
#!/usr/bin/env node
/**
 * PromptShield Review Logger
 * Reads a review report file and sends it to the gateway for dashboard visibility.
 * Also maintains a local review log at ~/.devguard/reviews.jsonl
 *
 * Usage:
 *   node review-logger.js --type review --report .promptshield/review-20260519-143022.md
 *   node review-logger.js --type session-end   (called by post-tool hook)
 */

const fs    = require("fs");
const path  = require("path");
const os    = require("os");
const http  = require("http");
const https = require("https");

const CONFIG      = path.join(os.homedir(), ".devguard", "config", "config.json");
const REVIEW_LOG  = path.join(os.homedir(), ".devguard", "reviews.jsonl");
const PS_DIR = path.join(process.cwd(), ".promptshield");
const LOCAL_STORE = path.join(PS_DIR, "reviews");

function cfg() {
  try { return JSON.parse(fs.readFileSync(CONFIG, "utf8")); }
  catch { return {}; }
}

function readStdin() {
  return new Promise(r => {
    if (process.stdin.isTTY) { r(null); return; }
    let d = "";
    process.stdin.setEncoding("utf8").on("data", c => d += c).on("end", () => {
      try { r(JSON.parse(d)); } catch { r({ raw: d }); }
    });
    setTimeout(() => r(null), 1000);
  });
}

// ── Parse CLI args ────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const typeIdx   = args.indexOf("--type");
const reportIdx = args.indexOf("--report");
const reviewType   = typeIdx   >= 0 ? args[typeIdx + 1]   : "review";
const reportFile   = reportIdx >= 0 ? args[reportIdx + 1] : null;

// ── Parse review report for structured data ────────────────────────────────
function parseReport(content) {
  const lines = content.split("\n");
  const result = {
    verdict: "PASS",
    filesReviewed: 0,
    blocking: 0,
    warnings: 0,
    deliberationStatus: "UNKNOWN",
    securityStatus: "PASS",
    testStatus: "UNKNOWN",
    qualityStatus: "PASS",
    summary: "",
  };

  for (const line of lines) {
    if (/verdict:\s*(PASS|WARN|BLOCK)/i.test(line)) result.verdict = line.match(/PASS|WARN|BLOCK/i)[0].toUpperCase();
    if (/files reviewed:\s*(\d+)/i.test(line)) result.filesReviewed = parseInt(line.match(/\d+/)[0]);
    if (/(\d+) blocking/i.test(line)) result.blocking = parseInt(line.match(/\d+/)[0]);
    if (/(\d+) warning/i.test(line)) result.warnings = parseInt(line.match(/\d+/)[0]);
    if (/deliberation.*:(ALIGNED|DEVIATION|CONTRADICTION)/i.test(line)) result.deliberationStatus = line.match(/ALIGNED|DEVIATION|CONTRADICTION/i)[0].toUpperCase();
    if (/security.*:(PASS|WARN|BLOCK)/i.test(line)) result.securityStatus = line.match(/PASS|WARN|BLOCK/i)[0].toUpperCase();
    if (/test coverage.*:(COMPLETE|PARTIAL|MISSING)/i.test(line)) result.testStatus = line.match(/COMPLETE|PARTIAL|MISSING/i)[0].toUpperCase();
    if (/code quality.*:(PASS|WARN|FAIL)/i.test(line)) result.qualityStatus = line.match(/PASS|WARN|FAIL/i)[0].toUpperCase();
  }

  // Extract first paragraph after ## Summary as the summary
  const summaryMatch = content.match(/## Summary\n([\s\S]*?)(?=\n##|$)/);
  if (summaryMatch) result.summary = summaryMatch[1].trim().slice(0, 500);

  return result;
}

// ── Send to gateway ───────────────────────────────────────────────────────────
function sendToGateway(gatewayUrl, token, payload) {
  return new Promise(resolve => {
    const isHttps = gatewayUrl.startsWith("https");
    const lib = isHttps ? https : http;
    const body = JSON.stringify(payload);
    const u = new URL("/api/v1/reviews", gatewayUrl);
    const req = lib.request({
      hostname: u.hostname,
      port: u.port || (isHttps ? 443 : 80),
      path: u.pathname,
      method: "POST",
      headers: {
        "content-type": "application/json",
        "content-length": Buffer.byteLength(body),
        "authorization": `Bearer ${token}`,
      }
    }, res => {
      res.on("data", () => {});
      res.on("end", () => resolve(res.statusCode < 300));
    });
    req.on("error", () => resolve(false));
    req.setTimeout(4000, () => { req.destroy(); resolve(false); });
    req.write(body);
    req.end();
  });
}

// ── Save locally ──────────────────────────────────────────────────────────────
function saveLocally(entry) {
  try {
    fs.appendFileSync(REVIEW_LOG, JSON.stringify(entry) + "\n");
  } catch { /* silent */ }
}

// ── Main ───────────────────────────────────────────────────────────────────────
async function main() {
  const c = cfg();
  const ts = new Date().toISOString();

  let reportContent = null;
  let parsed = {};

  // Read report file
  if (reportFile && fs.existsSync(reportFile)) {
    reportContent = fs.readFileSync(reportFile, "utf8");
    parsed = parseReport(reportContent);
  }

  // Also check stdin (piped report)
  const stdin = await readStdin();
  if (stdin?.report) {
    reportContent = stdin.report;
    parsed = parseReport(reportContent);
  }

  const entry = {
    ts,
    developer: c.developerName || "unknown",
    deviceName: c.developerName || os.hostname(),
    type: reviewType,
    verdict: parsed.verdict || "UNKNOWN",
    filesReviewed: parsed.filesReviewed || 0,
    blocking: parsed.blocking || 0,
    warnings: parsed.warnings || 0,
    deliberationStatus: parsed.deliberationStatus || "UNKNOWN",
    securityStatus: parsed.securityStatus || "PASS",
    testStatus: parsed.testStatus || "UNKNOWN",
    qualityStatus: parsed.qualityStatus || "PASS",
    summary: parsed.summary || "",
    reportFile: reportFile || null,
    cwd: process.cwd(),
  };

  // Always save locally
  saveLocally(entry);

  // Send to gateway (non-blocking — never fail the developer)
  if (c.gatewayUrl && c.developerToken) {
    await sendToGateway(c.gatewayUrl, c.developerToken, entry);
  }

  // Print confirmation
  const verdict = entry.verdict;
  const icon = verdict === "PASS" ? "✓" : verdict === "BLOCK" ? "✕" : "⚠";
  const color = verdict === "PASS" ? "\x1b[32m" : verdict === "BLOCK" ? "\x1b[31m" : "\x1b[33m";
  process.stderr.write(
    `\n${color}${icon} Review logged: ${verdict} — ${entry.blocking} blocking · ${entry.warnings} warnings\x1b[0m\n` +
    (reportFile ? `  Report: ${reportFile}\n` : "") +
    `  Saved:  ${REVIEW_LOG}\n\n`
  );

  process.exit(0);
}

main().catch(() => process.exit(0));
HEREDOC
chmod +x "${INSTALL_DIR}/bin/review-logger.js"

cat > "${INSTALL_DIR}/bin/generate-claude-md.js" << 'HEREDOC'
#!/usr/bin/env node
/**
 * PromptShield — Auto-generate CLAUDE.md
 * Called during install when CLAUDE.md is missing.
 * Scans the current project and generates context using Claude Haiku.
 */
const fs    = require("fs");
const path  = require("path");
const os    = require("os");
const https = require("https");

const CONFIG = path.join(os.homedir(), ".devguard", "config", "config.json");

function cfg() {
  try { return JSON.parse(fs.readFileSync(CONFIG, "utf8")); }
  catch { return {}; }
}

// ── Scan project for context clues ───────────────────────────────────────────
function scanProject() {
  const cwd = process.cwd();
  const clues = {};

  // Package.json → stack
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(cwd, "package.json"), "utf8"));
    clues.name = pkg.name || "";
    clues.description = pkg.description || "";
    clues.deps = Object.keys(pkg.dependencies || {}).slice(0, 10).join(", ");
    clues.scripts = Object.keys(pkg.scripts || {}).join(", ");
  } catch {}

  // Python → check requirements.txt
  try {
    const reqs = fs.readFileSync(path.join(cwd, "requirements.txt"), "utf8");
    clues.pythonDeps = reqs.split("\n").slice(0, 8).join(", ");
  } catch {}

  // README
  try {
    const readme = fs.readFileSync(path.join(cwd, "README.md"), "utf8");
    clues.readmeIntro = readme.split("\n").slice(0, 15).join("\n");
  } catch {}

  // Existing CLAUDE.md (even if partial)
  try {
    const existing = fs.readFileSync(path.join(cwd, ".promptshield", "CLAUDE.md"), "utf8");
    if (existing.trim().length > 50) clues.existingClaude = existing.slice(0, 500);
  } catch {}

  // Deliberation decisions
  try {
    const deliberationDir = path.join(cwd, ".promptshield", "deliberation");
    const slugs = fs.readdirSync(deliberationDir).filter(f => !f.startsWith("."));
    clues.deliberations = slugs.map(slug => {
      try {
        const dec = fs.readFileSync(path.join(deliberationDir, slug, "decision.md"), "utf8");
        const decisionLine = dec.split("\n").find(l => l.startsWith("## DECISION") || l.includes("DECISION:"));
        return `${slug}: ${decisionLine?.replace(/^#+\s*DECISION:?\s*/i, "").trim() || "see decision.md"}`;
      } catch { return slug; }
    }).join("\n");
  } catch {}

  // Git info
  try {
    const { execSync } = require("child_process");
    clues.repoName = execSync("git remote get-url origin 2>/dev/null").toString().trim().split("/").pop()?.replace(".git","") || "";
    clues.branch = execSync("git branch --show-current 2>/dev/null").toString().trim();
  } catch {}

  // Directory structure (top level)
  try {
    const entries = fs.readdirSync(cwd)
      .filter(f => !f.startsWith(".") && !["node_modules","__pycache__","dist","build"].includes(f))
      .slice(0, 12);
    clues.structure = entries.join(", ");
  } catch {}

  return clues;
}

async function generateViaClaude(clues) {
  const c = cfg();
  const apiKey = process.env.ANTHROPIC_API_KEY || c.anthropicApiKey || "";

  // Try gateway rewrite endpoint first (uses gateway's API key)
  if (c.gatewayUrl && c.developerToken) {
    const result = await callGateway(c.gatewayUrl, c.developerToken, clues);
    if (result) return result;
  }

  // Fall back to direct API
  if (!apiKey) return null;
  return callDirectAPI(apiKey, clues);
}

function callGateway(gatewayUrl, token, clues) {
  return new Promise(resolve => {
    const isHttps = gatewayUrl.startsWith("https");
    const lib = isHttps ? https : require("http");
    const body = JSON.stringify({ clues });
    const u = new URL("/api/v1/devguard/generate-claude-md", gatewayUrl);
    const req = lib.request({
      hostname: u.hostname, port: u.port || (isHttps?443:80),
      path: u.pathname, method: "POST",
      headers: { "content-type":"application/json", "content-length": Buffer.byteLength(body), "authorization":`Bearer ${token}` }
    }, res => {
      let d = "";
      res.on("data", c => d += c);
      res.on("end", () => { try { resolve(JSON.parse(d).content || null); } catch { resolve(null); } });
    });
    req.on("error", () => resolve(null));
    req.setTimeout(15000, () => { req.destroy(); resolve(null); });
    req.write(body); req.end();
  });
}

function callDirectAPI(apiKey, clues) {
  return new Promise(resolve => {
    const system = `You are PromptShield DevGuard. Generate a CLAUDE.md file for a developer's project.
Use the project clues provided. Be concise — this is read on every Claude Code session start.
Include: Project name/stack, sprint goal (placeholder), anti-patterns, gate rules, and role briefs.
Return ONLY the raw markdown content — no explanation, no code fences.`;

    const userMsg = `Generate CLAUDE.md for this project:

${JSON.stringify(clues, null, 2)}

Keep it under 60 lines. Make it practical and specific to this project.`;

    const body = JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 800,
      system,
      messages: [{ role: "user", content: userMsg }],
    });

    const req = https.request({
      hostname: "api.anthropic.com",
      path: "/v1/messages", method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
        "content-length": Buffer.byteLength(body),
      }
    }, res => {
      let d = "";
      res.on("data", c => d += c);
      res.on("end", () => {
        try { resolve(JSON.parse(d).content?.[0]?.text || null); }
        catch { resolve(null); }
      });
    });
    req.on("error", () => resolve(null));
    req.setTimeout(15000, () => { req.destroy(); resolve(null); });
    req.write(body); req.end();
  });
}

async function main() {
  const silent = process.argv.includes("--silent");
  if (!silent) process.stderr.write("  Scanning project...\n");

  const clues = scanProject();
  if (!silent) process.stderr.write("  Calling Claude Haiku to generate CLAUDE.md...\n");

  const content = await generateViaClaude(clues);

  if (!content) {
    process.exit(1); // Caller will fall back to template
  }

  const psDir = path.join(cwd, ".promptshield");
  require("fs").mkdirSync(psDir, { recursive: true });
  fs.writeFileSync(path.join(psDir, "CLAUDE.md"), content, "utf8");
  if (!silent) process.stderr.write(`  Generated .promptshield/CLAUDE.md (${content.length} chars)\n`);
  process.exit(0);
}

main().catch(() => process.exit(1));
HEREDOC
chmod +x "${INSTALL_DIR}/bin/generate-claude-md.js"

cat > "${INSTALL_DIR}/bin/session-start.js" << 'HEREDOC'
#!/usr/bin/env node
/**
 * PromptShield Session Start Checker
 *
 * Runs on first Claude Code prompt of each session.
 * Creates ALL missing project files inside .promptshield/
 * ONE folder — ONE gitignore entry: .promptshield/
 *
 * Structure created:
 *   .promptshield/
 *   ├── CLAUDE.md            project context
 *   ├── deliberation/        decision records (created by /kickoff)
 *   ├── specs/               feature specs (created by /kickoff)
 *   ├── claude-hooks/        Claude Code settings + commands
 *   │   ├── settings.json
 *   │   └── commands/
 *   ├── cursor-rules/        Cursor .mdc rules
 *   ├── reviews/             code review reports
 *   └── config.json          project-level config
 */

const fs       = require("fs");
const path     = require("path");
const os       = require("os");
const https    = require("https");
const http     = require("http");
const readline = require("readline");
const { PATHS, GLOBAL, CWD, readConfig, ensureDirs } = require("./paths.js");

// ── Colours ───────────────────────────────────────────────────────────────────
const C = {
  reset: "\x1b[0m", bold: "\x1b[1m",
  cyan: "\x1b[36m", green: "\x1b[32m",
  yellow: "\x1b[33m", red: "\x1b[31m", muted: "\x1b[90m"
};
const log  = m => process.stderr.write(m + "\n");
const ok   = m => log(`${C.green}✓${C.reset} ${m}`);
const warn = m => log(`${C.yellow}⚠${C.reset} ${m}`);
const info = m => log(`${C.cyan}ℹ${C.reset} ${m}`);
const head = m => log(`\n${C.bold}${C.cyan}${m}${C.reset}`);
const dim  = m => log(`${C.muted}${m}${C.reset}`);

// ── Rate limiting — only full check once per hour per project ─────────────────
function shouldRunCheck() {
  try {
    const s = JSON.parse(fs.readFileSync(PATHS.sessionState, "utf8"));
    if (s.cwd !== CWD) return true;
    return (Date.now() - new Date(s.ts).getTime()) > 60 * 60 * 1000;
  } catch { return true; }
}

function markChecked() {
  try {
    fs.mkdirSync(path.dirname(PATHS.sessionState), { recursive: true });
    fs.writeFileSync(PATHS.sessionState, JSON.stringify({ ts: new Date().toISOString(), cwd: CWD }));
  } catch {}
}

// ── Interactive prompt ────────────────────────────────────────────────────────
function ask(q) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stderr });
  return new Promise(r => { rl.question(`${C.yellow}?${C.reset} ${q} `, a => { rl.close(); r(a.trim()); }); });
}

// ── API call helper ───────────────────────────────────────────────────────────
function apiCall(gatewayUrl, token, method, apiPath, body) {
  return new Promise(resolve => {
    if (!gatewayUrl || !token) { resolve(null); return; }
    const isHttps = gatewayUrl.startsWith("https");
    const lib = isHttps ? https : http;
    const data = body ? JSON.stringify(body) : null;
    const u = new URL(apiPath, gatewayUrl);
    const req = lib.request({
      hostname: u.hostname, port: u.port || (isHttps ? 443 : 80),
      path: u.pathname, method,
      headers: { "content-type": "application/json", "authorization": `Bearer ${token}`, ...(data ? { "content-length": Buffer.byteLength(data) } : {}) }
    }, res => { let d = ""; res.on("data", c => d += c); res.on("end", () => { try { resolve(JSON.parse(d)); } catch { resolve(null); } }); });
    req.on("error", () => resolve(null));
    req.setTimeout(8000, () => { req.destroy(); resolve(null); });
    if (data) req.write(data);
    req.end();
  });
}

// ── Scan project for CLAUDE.md generation clues ───────────────────────────────
function scanProject() {
  const clues = { cwd: CWD };
  const skip = ["node_modules","__pycache__","dist","build",".git",".promptshield"];
  clues.structure = fs.readdirSync(CWD).filter(f=>!f.startsWith(".")&&!skip.includes(f)).slice(0,15).join(", ");
  try { const p=JSON.parse(fs.readFileSync(path.join(CWD,"package.json"),"utf8")); clues.name=p.name; clues.description=p.description; clues.deps=Object.keys(p.dependencies||{}).slice(0,10).join(", "); } catch {}
  try { clues.pythonDeps=fs.readFileSync(path.join(CWD,"requirements.txt"),"utf8").split("\n").slice(0,8).join(", "); } catch {}
  try { clues.readme=fs.readFileSync(path.join(CWD,"README.md"),"utf8").split("\n").slice(0,20).join("\n"); } catch {}
  // Also check inside .promptshield/deliberation for existing decisions
  try {
    const delibDir = PATHS.deliberation;
    const slugs = fs.readdirSync(delibDir).filter(f=>!f.startsWith(".")&&f!=="README.md");
    clues.decisions = slugs.map(slug => {
      try { const d=fs.readFileSync(path.join(delibDir,slug,"decision.md"),"utf8"); return `${slug}: ${d.split("\n").find(l=>l.includes("DECISION:"))?.replace(/^#+\s*DECISION:?\s*/i,"").trim()||"see decision.md"}`; }
      catch { return slug; }
    }).join("\n");
  } catch {}
  return clues;
}

// ── Generate CLAUDE.md via Claude Haiku ──────────────────────────────────────
async function generateCLAUDEmd(c) {
  const clues = scanProject();
  const system = `You are PromptShield DevGuard. Generate a CLAUDE.md for a developer's project.
Concise — read on every Claude Code session start. Include: project name/stack, sprint goal placeholder,
deliberation decisions (if any), two human gates, four role briefs, anti-patterns. Raw markdown only.`;

  // Try gateway first
  if (c.gatewayUrl && c.developerToken) {
    const r = await apiCall(c.gatewayUrl, c.developerToken, "POST", "/api/v1/devguard/generate-claude-md", { clues });
    if (r?.content) return r.content;
  }

  // Direct API fallback
  const apiKey = process.env.ANTHROPIC_API_KEY || c.anthropicApiKey || "";
  if (!apiKey) return null;

  return new Promise(resolve => {
    const body = JSON.stringify({ model: "claude-haiku-4-5-20251001", max_tokens: 800, system,
      messages: [{ role: "user", content: `Generate CLAUDE.md:\n${JSON.stringify(clues,null,2)}\nKeep under 60 lines.` }] });
    const req = https.request({ hostname: "api.anthropic.com", path: "/v1/messages", method: "POST",
      headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json", "content-length": Buffer.byteLength(body) }
    }, res => { let d=""; res.on("data",c=>d+=c); res.on("end",()=>{ try{resolve(JSON.parse(d).content?.[0]?.text||null);}catch{resolve(null);} }); });
    req.on("error",()=>resolve(null)); req.setTimeout(15000,()=>{req.destroy();resolve(null);});
    req.write(body); req.end();
  });
}

function loadTemplate() {
  try { return fs.readFileSync(GLOBAL.template, "utf8"); } catch {}
  return `# CLAUDE.md — [Your Project Name]
> Read on every Claude Code session start. Fill in your project details.
> Stored in .promptshield/CLAUDE.md — add .promptshield/ to .gitignore

## Project
Name: [your project name]
Stack: [e.g. Node.js, FastAPI, React, PostgreSQL]

## Current sprint
Goal: [what you are building this sprint]

Active stories:
- .promptshield/specs/[feature]/stories/001-[name].md

## Active deliberation decisions
> Do NOT contradict without reopening deliberation.
- .promptshield/deliberation/[feature]/decision.md: [one-line decision]

## Two human gates — absolute, no bypass
Gate 1: Human approves spec before implementation starts
Gate 2: Human approves before production deploy

## Four roles (ITM deliberation)
- Architect: long-term structure and composability
- Developer: simplest thing that works
- BA: is the user problem actually solved?
- QA: adversarial — what breaks at the edges?

Forbidden: "Sounds good" "I agree" "Fair point" "No objection" "Absolutely"

## Universal anti-patterns (all blocked)
1. Skip deliberation for any reason
2. Skip Gate 1 or Gate 2
3. Refactor during /bugfix
4. Self-merge PRs
5. Modify reproduction tests to pass
6. Combine test: and fix: commits
7. Improve adjacent code during a bugfix`;
}

// ── CHECK 1: .promptshield/ structure ────────────────────────────────────────
async function checkStructure() {
  const exists = fs.existsSync(PATHS.dir);
  if (exists) return true;

  head("┌─ PromptShield: First time in this project ─────────────────────");
  log("│");
  log("│  PromptShield will create ONE folder in your project:");
  log(`│  ${C.cyan}.promptshield/${C.reset}`);
  log("│");
  log("│  This folder contains everything PromptShield needs:");
  log("│  CLAUDE.md, deliberation records, specs, hooks, rules, reviews.");
  log("│");
  log("│  Add ONE line to your .gitignore and nothing is ever committed:");
  log(`│  ${C.cyan}.promptshield/${C.reset}`);
  log("│");
  log("│  [1] Create .promptshield/ and set up this project");
  log("│  [2] Skip — I'll set up manually");
  log("│");
  log("└────────────────────────────────────────────────────────────────");

  const choice = await ask("Choose [1/2]:");
  if (choice !== "2") {
    ensureDirs();
    ok(".promptshield/ structure created");
    return true;
  }
  warn("Skipped.");
  return false;
}

// ── CHECK 2: CLAUDE.md ────────────────────────────────────────────────────────
async function checkCLAUDEmd(c) {
  ensureDirs();
  const exists = fs.existsSync(PATHS.claudeMd) && fs.statSync(PATHS.claudeMd).size > 50;
  if (exists) { ok(`CLAUDE.md found (.promptshield/CLAUDE.md)`); return true; }

  head("┌─ PromptShield: CLAUDE.md missing ─────────────────────────────");
  log("│");
  log("│  CLAUDE.md = project context injected on every session start.");
  log("│  Without it, Claude starts cold — wasting tokens every session.");
  log("│");
  log(`│  Will be created at: ${C.cyan}.promptshield/CLAUDE.md${C.reset}`);
  log("│");
  log("│  [1] Auto-generate using Claude Haiku (~500 tokens) — recommended");
  log("│  [2] Copy starter template — I'll fill it in manually");
  log("│  [3] Skip for now");
  log("│");
  log("└────────────────────────────────────────────────────────────────");

  const choice = await ask("Choose [1/2/3]:");

  if (choice === "1") {
    log(""); dim("  Scanning project...");
    const content = await generateCLAUDEmd(c);
    if (content) {
      fs.writeFileSync(PATHS.claudeMd, content, "utf8");
      ok(`.promptshield/CLAUDE.md generated (${content.length} chars)`);
      log(""); dim("  Preview:"); content.split("\n").slice(0,6).forEach(l=>dim("  "+l)); dim("  ..."); log("");
      info("Edit .promptshield/CLAUDE.md to refine. Run 'team-claude sync' to push to all devices.");
      return true;
    }
    warn("Auto-generate failed — copying template");
    fs.writeFileSync(PATHS.claudeMd, loadTemplate(), "utf8");
    ok(".promptshield/CLAUDE.md created from template");
    info("Open .promptshield/CLAUDE.md and fill in the [bracketed] sections.");
    return false;
  }

  if (choice === "2") {
    fs.writeFileSync(PATHS.claudeMd, loadTemplate(), "utf8");
    ok(".promptshield/CLAUDE.md created from template");
    log(""); warn("Fill in the [bracketed] sections before starting:"); dim("  open .promptshield/CLAUDE.md"); log("");
    return false;
  }

  warn("Skipped — Claude starts without project context this session.");
  return false;
}

// ── CHECK 3: deliberation/ ───────────────────────────────────────────────────
async function checkDeliberation() {
  ensureDirs();
  const hasRecords = fs.existsSync(PATHS.deliberation) &&
    fs.readdirSync(PATHS.deliberation).filter(f=>!f.startsWith(".")&&f!=="README.md").length > 0;

  if (hasRecords) {
    const n = fs.readdirSync(PATHS.deliberation).filter(f=>!f.startsWith(".")&&f!=="README.md").length;
    ok(`.promptshield/deliberation/ found (${n} decision record${n!==1?"s":""})`);
    return true;
  }

  head("┌─ PromptShield: No deliberation records ───────────────────────");
  log("│");
  log("│  .promptshield/deliberation/ stores decision records.");
  log("│  Created automatically when you run /kickoff.");
  log("│");
  log("│  [1] Create empty structure — I'll populate via /kickoff");
  log("│  [2] Skip — deliberation records created automatically");
  log("│");
  log("└────────────────────────────────────────────────────────────────");

  const choice = await ask("Choose [1/2]:");

  if (choice === "1") {
    fs.mkdirSync(PATHS.deliberation, { recursive: true });
    fs.writeFileSync(path.join(PATHS.deliberation, "README.md"),
`# .promptshield/deliberation/

Stores ITM deliberation decision records. Created by /kickoff.

## Structure
\`\`\`
deliberation/
  <feature-slug>/
    transcript.json     ← full deliberation transcript
    decision.md         ← final decision record
    verification.json   ← 11-check verifier results
    state.json          ← workflow state
\`\`\`

## Creating records
Run: /kickoff "your feature description"
`);
    ok(".promptshield/deliberation/ structure created");
    info("Run /kickoff \"your feature\" to create your first decision record.");
    return true;
  }

  warn("Skipped — run /kickoff to create deliberation records.");
  return false;
}

// ── CHECK 4: specs/ ───────────────────────────────────────────────────────────
async function checkSpecs() {
  ensureDirs();
  const hasSpecs = fs.existsSync(PATHS.specs) &&
    fs.readdirSync(PATHS.specs).filter(f=>!f.startsWith(".")&&f!=="README.md").length > 0;

  if (hasSpecs) { ok(".promptshield/specs/ found"); return true; }

  fs.mkdirSync(PATHS.specs, { recursive: true });
  fs.writeFileSync(path.join(PATHS.specs, "README.md"),
`# .promptshield/specs/

Feature specs, stories, and acceptance criteria. Created by /kickoff and /brd.

\`\`\`
specs/
  <feature-slug>/
    brief.md
    prd.md
    architecture.md
    risk-log.md
    stories/
      001-<name>.md
\`\`\`
`);
  ok(".promptshield/specs/ structure created");
  return true;
}

// ── CHECK 5: Claude Code hooks ────────────────────────────────────────────────
async function checkClaudeHooks() {
  ensureDirs();

  // Check if .claude/settings.json symlinks or references .promptshield/claude-hooks
  const settingsPath = path.join(CWD, ".claude", "settings.json");
  const psSettings   = PATHS.claudeSettings;

  if (fs.existsSync(psSettings)) {
    // Ensure .claude/settings.json points to our hooks
    if (!fs.existsSync(settingsPath)) {
      fs.mkdirSync(path.join(CWD, ".claude"), { recursive: true });
      fs.writeFileSync(settingsPath, fs.readFileSync(psSettings, "utf8"));
    }
    ok(".promptshield/claude-hooks/ (DevGuard hooks) found");
    return true;
  }

  head("┌─ PromptShield: Claude Code hooks not installed ───────────────");
  log("│");
  log("│  Hooks fire before/after every Claude Code tool call.");
  log("│  Without them, DevGuard cannot validate prompts.");
  log(`│  Stored in: ${C.cyan}.promptshield/claude-hooks/${C.reset}`);
  log("│");
  log("│  [1] Install hooks now (recommended)");
  log("│  [2] Skip");
  log("│");
  log("└────────────────────────────────────────────────────────────────");

  const choice = await ask("Choose [1/2]:");

  if (choice !== "2") {
    fs.mkdirSync(PATHS.claudeCommands, { recursive: true });

    const settings = {
      hooks: {
        PreToolUse:  [{ matcher: ".*", hooks: [{ type: "command", command: "node ~/.devguard/bin/pre-tool-hook.js"   }] }],
        PostToolUse: [{ matcher: ".*", hooks: [{ type: "command", command: "node ~/.devguard/bin/usage-reporter.js" }] }],
      }
    };
    fs.writeFileSync(psSettings, JSON.stringify(settings, null, 2));

    // Mirror to .claude/settings.json so Claude Code picks it up
    fs.mkdirSync(path.join(CWD, ".claude"), { recursive: true });
    fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));

    // Write slim command stubs
    const commands = {
      "kickoff.md":   `---\ndescription: New feature with deliberation. Stores records in .promptshield/deliberation/\n---\n# Kickoff\n$ARGUMENTS\nRun deliberation → saves to .promptshield/deliberation/<slug>/ → Gate 1 PR. BLOCK if deliberation skipped.`,
      "bugfix.md":    `---\ndescription: TDD bug fix. Ask for review when done.\n---\n# Bugfix\n$ARGUMENTS\nWrite failing test first. Minimal fix only. At end ask: Do you want to run a PromptShield review?`,
      "implement.md": `---\ndescription: Build approved story. Ask for review when done.\n---\n# Implement\n$ARGUMENTS\nLoad .promptshield/deliberation/<slug>/decision.md first. At end ask: Do you want to run a PromptShield review?`,
      "ship.md":      `---\ndescription: Deploy to production. Gate 2 required.\n---\n# Ship\n$ARGUMENTS\nDeliberation verification must PASS. Gate 2 human approval required. Never bypass.`,
      "review.md":    `---\ndescription: Code review on git diff. Saves report to .promptshield/reviews/\n---\n# Review\n$ARGUMENTS\nCheck: deliberation alignment, acceptance criteria, code quality, security, tests.\nSave report to .promptshield/reviews/review-<timestamp>.md and log to gateway.`,
      "devguard.md":  `---\ndescription: Validate any prompt against DevGuard rules\n---\n# DevGuard\nValidate: $ARGUMENTS\nCheck L1 quality + L2 workflow compliance. Return corrected prompt if blocked.`,
    };

    for (const [name, content] of Object.entries(commands)) {
      const cmdPath = path.join(PATHS.claudeCommands, name);
      if (!fs.existsSync(cmdPath)) fs.writeFileSync(cmdPath, content);
      // Also mirror to .claude/commands/ for Claude Code
      const claudeCmdPath = path.join(CWD, ".claude", "commands", name);
      if (!fs.existsSync(claudeCmdPath)) {
        fs.mkdirSync(path.dirname(claudeCmdPath), { recursive: true });
        fs.writeFileSync(claudeCmdPath, content);
      }
    }

    ok(".promptshield/claude-hooks/ installed");
    info("DevGuard will validate every Claude Code prompt in this project.");
    return true;
  }

  warn("Skipped — prompts will not be validated.");
  return false;
}

// ── CHECK 6: Cursor rules ─────────────────────────────────────────────────────
async function checkCursorRules() {
  ensureDirs();
  const hasRules = fs.existsSync(PATHS.cursorRules) &&
    fs.readdirSync(PATHS.cursorRules).filter(f=>f.endsWith(".mdc")).length > 0;
  if (hasRules) { ok(".promptshield/cursor-rules/ found"); return true; }

  const cursorDetected = fs.existsSync(path.join(CWD, ".cursor")) ||
    process.env.TERM_PROGRAM === "cursor";
  if (!cursorDetected) return true;

  head("┌─ PromptShield: Cursor rules not installed ─────────────────────");
  log("│");
  log(`│  Stored in: ${C.cyan}.promptshield/cursor-rules/${C.reset}`);
  log("│  [1] Install   [2] Skip");
  log("└────────────────────────────────────────────────────────────────");

  const choice = await ask("Choose [1/2]:");
  if (choice !== "2") {
    fs.mkdirSync(PATHS.cursorRules, { recursive: true });
    fs.writeFileSync(path.join(PATHS.cursorRules,"devguard-always-on.mdc"),
`---\ndescription: DevGuard — validates every prompt. Always active.\nglobs:\nalwaysApply: true\n---\n\n# DevGuard Always-On\n\nBLOCK: "while you're there" | "skip deliberation" | "skip gate" | "merge myself" | "fix all issues"\nWARN: refactor in /bugfix | vague outcome without metric\n\nAll files stored in .promptshield/ — one .gitignore entry covers everything.\nAlways provide corrected prompt when blocking. Never just reject.`);
    fs.writeFileSync(path.join(PATHS.cursorRules,"project-context.mdc"),
`---\ndescription: Project context — read .promptshield/CLAUDE.md every session.\nglobs:\nalwaysApply: true\n---\n\n# Project Context\n\nRead .promptshield/CLAUDE.md at session start — contains sprint goal, decisions, anti-patterns.\nGate 1: Human approves spec before implementation.\nGate 2: Human approves before production deploy.\nForbidden in deliberation: "Sounds good" "I agree" "Fair point" "No objection"`);

    // Mirror to .cursor/rules/ so Cursor picks them up
    const cursorRulesDir = path.join(CWD, ".cursor", "rules");
    fs.mkdirSync(cursorRulesDir, { recursive: true });
    for (const f of fs.readdirSync(PATHS.cursorRules)) {
      fs.writeFileSync(path.join(cursorRulesDir,f), fs.readFileSync(path.join(PATHS.cursorRules,f),"utf8"));
    }

    ok(".promptshield/cursor-rules/ installed (mirrored to .cursor/rules/)");
    return true;
  }
  warn("Skipped.");
  return false;
}

// ── CHECK 7: .gitignore ───────────────────────────────────────────────────────
async function checkGitignore() {
  const gitignorePath = path.join(CWD, ".gitignore");
  const globalIgnore  = path.join(os.homedir(), ".gitignore_global");

  // Check if .promptshield/ is already ignored
  try { if (fs.readFileSync(globalIgnore,"utf8").includes(".promptshield/")) return true; } catch {}
  try { if (fs.readFileSync(gitignorePath,"utf8").includes(".promptshield/")) return true; } catch {}

  head("┌─ PromptShield: .gitignore not configured ──────────────────────");
  log("│");
  log("│  Add ONE line and nothing PromptShield creates is ever committed:");
  log(`│  ${C.cyan}.promptshield/${C.reset}`);
  log("│");
  log("│  [1] Add to global ~/.gitignore_global (covers ALL repos) — recommended");
  log("│  [2] Add to this project's .gitignore only");
  log("│  [3] Skip — I'll do it myself");
  log("│");
  log("└────────────────────────────────────────────────────────────────");

  const choice = await ask("Choose [1/2/3]:");
  const entry = "\n# PromptShield — local only, do not commit\n.promptshield/\n";

  if (choice === "1") {
    fs.appendFileSync(globalIgnore, entry);
    try { require("child_process").execSync(`git config --global core.excludesfile ${globalIgnore}`); } catch {}
    ok("~/.gitignore_global updated — .promptshield/ ignored in all repos");
    return true;
  }
  if (choice === "2") {
    fs.appendFileSync(gitignorePath, entry);
    ok(".gitignore updated — .promptshield/ will not be committed");
    return true;
  }
  warn("Remember to add .promptshield/ to your .gitignore.");
  return false;
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  const force  = process.argv.includes("--force");
  const silent = process.argv.includes("--silent");

  if (silent) { process.exit(0); }
  if (!force && !shouldRunCheck()) { process.exit(0); }

  const c = readConfig();

  log("");
  log(`${C.bold}${C.cyan}⬡ PromptShield — Project setup check${C.reset}`);
  log(`${C.muted}  All files → .promptshield/   One gitignore entry covers everything.${C.reset}`);
  log(`${C.muted}  Project: ${CWD}${C.reset}`);
  log("");

  let issues = 0;
  const ok1 = await checkStructure();
  if (!ok1) { markChecked(); process.exit(0); }

  const r2 = await checkCLAUDEmd(c);     if (!r2) issues++;
  const r3 = await checkDeliberation();  if (!r3) issues++;
  const r4 = await checkSpecs();
  const r5 = await checkClaudeHooks();   if (!r5) issues++;
  const r6 = await checkCursorRules();
  const r7 = await checkGitignore();     if (!r7) issues++;

  log("");
  if (issues === 0) {
    log(`${C.green}${C.bold}✓ PromptShield ready — all files in .promptshield/${C.reset}`);
  } else {
    log(`${C.yellow}⚠ ${issues} item${issues!==1?"s":""} still need attention — see above${C.reset}`);
    log(`${C.muted}  Run 'team-claude check' to re-check anytime${C.reset}`);
  }
  log("");
  log(`${C.muted}  .promptshield/ structure:${C.reset}`);
  log(`${C.muted}  ├── CLAUDE.md         project context${C.reset}`);
  log(`${C.muted}  ├── deliberation/     decision records (created by /kickoff)${C.reset}`);
  log(`${C.muted}  ├── specs/            feature specs (created by /kickoff)${C.reset}`);
  log(`${C.muted}  ├── claude-hooks/     Claude Code settings + commands${C.reset}`);
  log(`${C.muted}  ├── cursor-rules/     Cursor .mdc rules${C.reset}`);
  log(`${C.muted}  └── reviews/          code review reports${C.reset}`);
  log("");

  markChecked();
  process.exit(0);
}

main().catch(e => {
  process.stderr.write(`\n${C.muted}PromptShield check error: ${e.message}${C.reset}\n`);
  process.exit(0); // Never block Claude Code
});
HEREDOC
chmod +x "${INSTALL_DIR}/bin/session-start.js"

cat > "${INSTALL_DIR}/bin/paths.js" << 'HEREDOC'
/**
 * PromptShield — Canonical path definitions
 * ALL project-level files live under .promptshield/ in the project root.
 * ONE gitignore entry covers everything: .promptshield/
 *
 * Global files (device config, installed binaries) live under ~/.devguard/
 */

const path = require("path");
const os   = require("os");

// ── Project root — where .promptshield/ lives ─────────────────────────────────
const CWD = process.cwd();

// ── The one folder that covers everything ─────────────────────────────────────
const PS_DIR = path.join(CWD, ".promptshield");

// ── Project-level paths (all inside .promptshield/) ───────────────────────────
const PATHS = {
  // Root
  dir:              PS_DIR,

  // CLAUDE.md — project context
  claudeMd:         path.join(PS_DIR, "CLAUDE.md"),

  // Deliberation records — .promptshield/deliberation/<slug>/
  deliberation:     path.join(PS_DIR, "deliberation"),

  // Feature specs — .promptshield/specs/<feature>/stories/
  specs:            path.join(PS_DIR, "specs"),

  // Claude Code hooks — .promptshield/claude-hooks/
  claudeHooks:      path.join(PS_DIR, "claude-hooks"),
  claudeSettings:   path.join(PS_DIR, "claude-hooks", "settings.json"),
  claudeCommands:   path.join(PS_DIR, "claude-hooks", "commands"),

  // Cursor rules — .promptshield/cursor-rules/
  cursorRules:      path.join(PS_DIR, "cursor-rules"),

  // Review reports — .promptshield/reviews/
  reviews:          path.join(PS_DIR, "reviews"),

  // Local project config (gateway URL override, project name, etc.)
  config:           path.join(PS_DIR, "config.json"),

  // Session state (last check time)
  sessionState:     path.join(PS_DIR, ".session-state.json"),
};

// ── Global device paths (per machine, under ~/.devguard/) ─────────────────────
const HOME = os.homedir();
const GLOBAL = {
  dir:       path.join(HOME, ".devguard"),
  config:    path.join(HOME, ".devguard", "config", "config.json"),
  template:  path.join(HOME, ".devguard", "templates", "CLAUDE.md.template"),
  reviewLog: path.join(HOME, ".devguard", "reviews.jsonl"),
  queue:     path.join(HOME, ".devguard", "queue.jsonl"),
  bin:       path.join(HOME, ".devguard", "bin"),
};

// ── Read project config (merges with global config) ───────────────────────────
function readConfig() {
  let global = {};
  let project = {};
  try { global  = JSON.parse(require("fs").readFileSync(GLOBAL.config,  "utf8")); } catch {}
  try { project = JSON.parse(require("fs").readFileSync(PATHS.config, "utf8")); } catch {}
  return { ...global, ...project }; // project overrides global
}

// ── Ensure .promptshield/ structure exists ────────────────────────────────────
function ensureDirs() {
  const fs = require("fs");
  const dirs = [
    PATHS.dir,
    PATHS.deliberation,
    PATHS.specs,
    PATHS.claudeHooks,
    PATHS.claudeCommands,
    PATHS.cursorRules,
    PATHS.reviews,
  ];
  for (const d of dirs) {
    fs.mkdirSync(d, { recursive: true });
  }
}

module.exports = { PATHS, GLOBAL, CWD, readConfig, ensureDirs };
HEREDOC
chmod +x "${INSTALL_DIR}/bin/paths.js"

# Write config
cat > "${INSTALL_DIR}/config/config.json" << CONFIG
{
  "version": "${VERSION}",
  "developerToken": "${DEVICE_ID}",
  "developerName": "${NAME}",
  "gatewayUrl": "${GATEWAY_URL}",
  "mode": "${MODE}",
  "os": "${OS_TYPE}",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown')"
}
CONFIG
ok "Core installed at ${INSTALL_DIR}"

# Download CLAUDE.md template
mkdir -p "${INSTALL_DIR}/templates"
curl -fsSL "${RAW}/templates/CLAUDE.md.template" -o "${INSTALL_DIR}/templates/CLAUDE.md.template" 2>/dev/null || true

# ── Install team-claude CLI (embedded) ────────────────────────────────────────
step "Installing team-claude CLI..."
mkdir -p /tmp/ps-cli-install
cat > "/tmp/ps-cli-install/team-claude.js" << 'HEREDOC'
#!/usr/bin/env node
/**
 * team-claude — PromptShield developer CLI
 * Wraps Claude API through the gateway with auth, DevGuard, and token tracking.
 */
const { program } = require("commander");
const fs  = require("fs");
const os  = require("os");
const path = require("path");
const readline = require("readline");
const https = require("https");

const CONFIG_FILE = path.join(os.homedir(), ".devguard", "config", "config.json");

function readConfig() {
  try { return JSON.parse(fs.readFileSync(CONFIG_FILE, "utf8")); }
  catch { return {}; }
}
function writeConfig(cfg) {
  fs.mkdirSync(path.dirname(CONFIG_FILE), { recursive: true });
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2));
}

function gatewayRequest(method, path, body, token) {
  const cfg = readConfig();
  const base = cfg.gatewayUrl || "http://localhost:8000";
  return new Promise((resolve, reject) => {
    const url = new URL(path, base);
    const isHttps = url.protocol === "https:";
    const lib = isHttps ? require("https") : require("http");
    const data = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: url.hostname, port: url.port || (isHttps ? 443 : 80),
      path: url.pathname, method,
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token || cfg.developerToken || ""}`,
        ...(data ? { "Content-Length": Buffer.byteLength(data) } : {}),
      }
    };
    const req = lib.request(opts, res => {
      let d = "";
      res.on("data", c => { d += c; });
      res.on("end", () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(d) }); }
        catch { resolve({ status: res.statusCode, body: d }); }
      });
    });
    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

program.name("team-claude").description("PromptShield developer CLI").version("1.0.0");

// ── login ────────────────────────────────────────────────────────────────────
program.command("login")
  .description("Authenticate with your PromptShield token")
  .action(async () => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question("Paste your PromptShield token: ", async (token) => {
      rl.close();
      token = token.trim();
      if (!token) { console.error("Token required"); process.exit(1); }
      try {
        const res = await gatewayRequest("POST", "/api/v1/developers/register",
          { name: os.userInfo().username }, token);
        if (res.status === 200) {
          const cfg = readConfig();
          cfg.developerToken = token;
          writeConfig(cfg);
          console.log(`✓ Logged in as ${res.body.developer || "developer"}`);
        } else {
          console.error("✕ Login failed:", res.body?.detail || "Invalid token");
          process.exit(1);
        }
      } catch (e) {
        console.error("✕ Cannot reach gateway:", e.message);
        process.exit(1);
      }
    });
  });

// ── config ────────────────────────────────────────────────────────────────────
program.command("config <action> <key> [value]")
  .description("Get or set config values")
  .action((action, key, value) => {
    const cfg = readConfig();
    if (action === "set") { cfg[key] = value; writeConfig(cfg); console.log(`✓ Set ${key}`); }
    else if (action === "get") { console.log(cfg[key] || "(not set)"); }
    else { console.log(JSON.stringify(cfg, null, 2)); }
  });

// ── status ────────────────────────────────────────────────────────────────────
program.command("status")
  .description("Your usage vs quota")
  .action(async () => {
    const cfg = readConfig();
    if (!cfg.developerToken) { console.error("Not logged in. Run: team-claude login"); process.exit(1); }
    try {
      const res = await gatewayRequest("GET", "/api/v1/usage/me");
      if (res.status !== 200) { console.error("Could not fetch status"); return; }
      const d = res.body;
      const barWidth = 30;
      const bar = (used, max) => {
        const p = Math.min(1, used / max);
        const filled = Math.round(p * barWidth);
        return "[" + "█".repeat(filled) + "░".repeat(barWidth - filled) + "]";
      };
      console.log(`\nPromptShield — ${cfg.developerName || "Developer"}\n`);
      console.log(`Daily:   ${bar(d.tokensToday, d.dailyLimit)} ${(d.tokensToday/1000).toFixed(0)}k / ${(d.dailyLimit/1000).toFixed(0)}k tokens`);
      console.log(`Monthly: ${bar(d.tokensMonth, d.monthlyLimit)} ${(d.tokensMonth/1000000).toFixed(2)}M / ${(d.monthlyLimit/1000000).toFixed(1)}M tokens`);
      console.log(`Cost MTD: $${d.costMonth?.toFixed(2) || "0.00"}`);
      console.log(`DevGuard: ${d.passed || 0} passed · ${d.warned || 0} warned · ${d.blocked || 0} blocked\n`);
    } catch (e) {
      console.error("Gateway unreachable:", e.message);
    }
  });

// ── chat ──────────────────────────────────────────────────────────────────────
program.command("chat")
  .description("Start a chat session through the gateway")
  .option("-m, --model <model>", "Claude model", "claude-sonnet-4-6")
  .action(async (opts) => {
    const cfg = readConfig();
    if (!cfg.developerToken) { console.error("Not logged in. Run: team-claude login"); process.exit(1); }
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const history = [];
    console.log('\nPromptShield Chat (type "exit" to quit)\n');
    const ask = () => {
      rl.question("You: ", async (input) => {
        if (!input.trim() || input.trim() === "exit") { rl.close(); return; }
        history.push({ role: "user", content: input });
        try {
          const res = await gatewayRequest("POST", "/v1/messages", {
            model: opts.model,
            max_tokens: 1024,
            messages: history,
          });
          if (res.status === 422 && res.body?.error?.type === "devguard_block") {
            console.log(`\nDevGuard BLOCK [${res.body.error.rule}]: ${res.body.error.message}`);
            if (res.body.error.corrected_prompt) {
              console.log(`\nCorrected prompt:\n${res.body.error.corrected_prompt}\n`);
            }
            history.pop();
          } else if (res.status === 200) {
            const text = res.body.content?.[0]?.text || "";
            history.push({ role: "assistant", content: text });
            console.log(`\nClaude: ${text}\n`);
          } else {
            console.error("Error:", res.body?.error?.message || res.status);
            history.pop();
          }
        } catch (e) {
          console.error("Gateway error:", e.message);
          history.pop();
        }
        ask();
      });
    };
    ask();
  });

// ── prompt (one-shot) ─────────────────────────────────────────────────────────
program.command("prompt <text>")
  .description("Send a single prompt through the gateway")
  .option("-m, --model <model>", "Claude model", "claude-sonnet-4-6")
  .action(async (text, opts) => {
    const cfg = readConfig();
    if (!cfg.developerToken) { console.error("Not logged in. Run: team-claude login"); process.exit(1); }
    const res = await gatewayRequest("POST", "/v1/messages", {
      model: opts.model, max_tokens: 1024,
      messages: [{ role: "user", content: text }],
    });
    if (res.status === 422 && res.body?.error?.type === "devguard_block") {
      console.error(`DevGuard BLOCK: ${res.body.error.message}`);
      if (res.body.error.corrected_prompt) console.log(`\nCorrected:\n${res.body.error.corrected_prompt}`);
      process.exit(1);
    }
    console.log(res.body.content?.[0]?.text || JSON.stringify(res.body));
  });

// ── init — generate CLAUDE.md ────────────────────────────────────────────────
program.command("init")
  .description("Generate CLAUDE.md for the current project")
  .action(async () => {
    const genScript = path.join(os.homedir(), ".devguard", "bin", "generate-claude-md.js");
    if (!fs.existsSync(genScript)) {
      console.error("generate-claude-md.js not found. Re-run the PromptShield installer.");
      process.exit(1);
    }
    const { spawnSync } = require("child_process");
    const result = spawnSync("node", [genScript], { stdio: "inherit", cwd: process.cwd() });
    if (result.status === 0) {
      console.log("✓ CLAUDE.md generated. Review and edit it to match your project.");
    } else {
      console.error("✕ Could not auto-generate. Copying starter template...");
      const templatePath = path.join(os.homedir(), ".devguard", "templates", "CLAUDE.md.template");
      if (fs.existsSync(templatePath)) {
        fs.copyFileSync(templatePath, path.join(process.cwd(), "CLAUDE.md"));
        console.log("✓ Starter CLAUDE.md copied. Fill in the [bracketed] sections.");
      } else {
        console.error("Template not found. Run the PromptShield installer again.");
      }
    }
  });

// ── check — run session start check manually ─────────────────────────────────
program.command("check")
  .description("Check all required PromptShield files for this project")
  .action(() => {
    const checkScript = path.join(os.homedir(), ".devguard", "bin", "session-start.js");
    if (!fs.existsSync(checkScript)) {
      console.error("session-start.js not found. Re-run the PromptShield installer.");
      process.exit(1);
    }
    const { spawnSync } = require("child_process");
    spawnSync("node", [checkScript, "--force"], { stdio: "inherit", cwd: process.cwd() });
  });

// ── sync — pull latest CLAUDE.md from gateway ────────────────────────────────
program.command("sync")
  .description("Sync latest CLAUDE.md from gateway to this device")
  .action(() => {
    const syncScript = path.join(os.homedir(), ".devguard", "bin", "claude-md-sync.js");
    if (!fs.existsSync(syncScript)) { console.error("sync script not found"); process.exit(1); }
    const { spawnSync } = require("child_process");
    spawnSync("node", [syncScript], { stdio: "inherit", cwd: process.cwd() });
  });

program.parse(process.argv);
HEREDOC
chmod +x "/tmp/ps-cli-install/team-claude.js"
cat > "/tmp/ps-cli-install/package.json" << 'HEREDOC'
{
  "name": "team-claude",
  "version": "1.0.0",
  "description": "PromptShield developer CLI — gateway-aware Claude wrapper",
  "main": "team-claude.js",
  "bin": { "team-claude": "./team-claude.js" },
  "dependencies": { "commander": "^12.1.0" },
  "engines": { "node": ">=18" }
}
HEREDOC
cd /tmp/ps-cli-install && npm install --silent 2>/dev/null
npm install -g . --silent 2>/dev/null || {
  # Fallback: manual bin link
  cp team-claude.js "${INSTALL_DIR}/bin/team-claude"
  chmod +x "${INSTALL_DIR}/bin/team-claude"
  # Windows: create .cmd wrapper
  if [[ "$OS_TYPE" == "windows-bash" ]]; then
    echo "@node "%~dp0team-claude" %*" > "${BIN_DIR}/team-claude.cmd"
  fi
  ln -sf "${INSTALL_DIR}/bin/team-claude" "${BIN_DIR}/team-claude" 2>/dev/null || true
}
cd - >/dev/null
ok "team-claude CLI installed"

# ── Install Cursor rules ──────────────────────────────────────────────────────
if ! $SKIP_CURSOR; then
  step "Installing Cursor rules..."
  if [[ -d ".cursor" ]] || check_cmd cursor; then
    mkdir -p .cursor/rules
    for rule in devguard-always-on.mdc project-context.mdc kickoff.mdc bugfix.mdc implement.mdc enhance.mdc ship.mdc brd.mdc; do
      if check_cmd curl; then
        curl -fsSL "${RAW}/.cursor/rules/${rule}" -o ".cursor/rules/${rule}" 2>/dev/null || true
      else
        wget -q "${RAW}/.cursor/rules/${rule}" -O ".cursor/rules/${rule}" 2>/dev/null || true
      fi
    done
    ok "Cursor rules installed"
  else
    warn "Cursor not detected — run from project root after opening Cursor"
  fi
fi

# ── Install Claude Code hooks ─────────────────────────────────────────────────
if ! $SKIP_CLAUDE; then
  step "Installing Claude Code hooks..."
  if check_cmd claude; then
    mkdir -p .claude/commands
    for cmd in devguard.md kickoff.md bugfix.md implement.md ship.md enhance.md brd.md; do
      if check_cmd curl; then
        curl -fsSL "${RAW}/.claude/commands/${cmd}" -o ".claude/commands/${cmd}" 2>/dev/null || true
      else
        wget -q "${RAW}/.claude/commands/${cmd}" -O ".claude/commands/${cmd}" 2>/dev/null || true
      fi
    done
    if check_cmd curl; then
      curl -fsSL "${RAW}/.claude/settings.json" -o ".claude/settings.json" 2>/dev/null || true
    fi
    ok "Claude Code hooks installed"
  else
    warn "Claude Code CLI not found — install it (see README) then re-run with --no-cursor"
  fi
fi

# ── Sync CLAUDE.md ────────────────────────────────────────────────────────────
step "Syncing CLAUDE.md from gateway..."
node "${INSTALL_DIR}/bin/claude-md-sync.js" --silent 2>/dev/null && ok "CLAUDE.md synced" || {
  warn "Could not sync CLAUDE.md from gateway — will check on first use"
}

# ── Add to PATH ───────────────────────────────────────────────────────────────
if [[ "$OS_TYPE" == "mac" || "$OS_TYPE" == "linux" ]]; then
  SHELL_RC="$HOME/.zshrc"
  [[ "$SHELL" == */bash ]] && SHELL_RC="$HOME/.bashrc"
  grep -q ".local/bin" "$SHELL_RC" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
elif [[ "$OS_TYPE" == "windows-bash" ]]; then
  SHELL_RC="$HOME/.bashrc"
  grep -q ".local/bin" "$SHELL_RC" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
fi

# ── Register with gateway ─────────────────────────────────────────────────────
step "Registering device with gateway..."
REG_PAYLOAD="{\"name\":\"${NAME}\",\"os\":\"${OS_TYPE}\",\"mode\":\"${MODE}\",\"version\":\"${VERSION}\"}"
if check_cmd curl; then
  curl -fsSL -X POST "${GATEWAY_URL}/api/v1/developers/register" \
    -H "Authorization: Bearer ${DEVICE_ID}" \
    -H "Content-Type: application/json" \
    -d "$REG_PAYLOAD" >/dev/null 2>&1 && ok "Registered with gateway" || warn "Gateway offline — will register when connected"
fi

# ── Check for empty CLAUDE.md and deliberation ───────────────────────────────
echo ""
step "Checking project files..."

CLAUDE_MD_EXISTS=false
DELIB_EXISTS=false

[[ -f "CLAUDE.md" && -s "CLAUDE.md" ]] && CLAUDE_MD_EXISTS=true
[[ -d ".deliberation" && $(ls -A .deliberation 2>/dev/null | wc -l) -gt 0 ]] && DELIB_EXISTS=true

if ! $CLAUDE_MD_EXISTS; then
  echo ""
  echo -e "${YELLOW}⚠ CLAUDE.md not found or empty in this directory.${NC}"
  echo ""
  echo "  CLAUDE.md gives Claude context about your project on every session."
  echo "  Without it, Claude starts cold every time — wasting tokens."
  echo ""
  echo "  Options:"
  echo "  [1] Auto-generate using Claude API (uses ~500 tokens)"
  echo "  [2] Copy a starter template (no tokens used)"
  echo "  [3] Skip for now"
  echo ""
  ask "Choose [1/2/3]:"
  read -r CLAUDE_CHOICE

  case "${CLAUDE_CHOICE:-3}" in
    1)
      step "Generating CLAUDE.md using Claude..."
      node "${INSTALL_DIR}/bin/generate-claude-md.js" 2>/dev/null \
        && ok "CLAUDE.md generated" \
        || {
          warn "Auto-generate failed — copying starter template instead"
          CLAUDE_CHOICE="2"
        }
      ;;
    2|"")
      if check_cmd curl; then
        curl -fsSL "${RAW}/templates/CLAUDE.md.template" -o CLAUDE.md 2>/dev/null \
          && ok "Starter CLAUDE.md copied — open it and fill in your project details" \
          || {
            # Inline fallback template
            cat > CLAUDE.md << 'MDEOF'
# CLAUDE.md — [Your Project Name]
> Read on every session start. Fill this in with your project details.

## Project
Name: [your project name]
Stack: [e.g. Node.js, FastAPI, React, PostgreSQL]
Repo: [github.com/your-org/your-repo]

## Current sprint
Goal: [what you're building this sprint]

Active stories:
- specs/[feature]/stories/001-[name].md

## Active deliberation decisions
> Do not contradict these without reopening deliberation.
- .deliberation/[feature]/decision.md: [one-line decision]

## Roles (ITM Deliberation)
- Architect: long-term structure and composability
- Developer: simplest thing that works
- BA: is the user's problem actually solved?
- QA: adversarial — what breaks at the edges?

Forbidden phrases: "Sounds good" "I agree" "Fair point" "No objection"

## Two human gates (absolute — no bypass)
Gate 1: Human approves spec before implementation
Gate 2: Human approves before production deploy

## Universal anti-patterns (all blocked)
1. Skip deliberation for any reason
2. Skip Gate 1 or Gate 2
3. Refactor during /bugfix
4. Self-merge PRs
5. Modify reproduction tests to pass
6. Combine test: and fix: commits
7. Improve adjacent code during a bugfix
MDEOF
            ok "Starter CLAUDE.md created — edit it with your project details"
          }
      fi
      ;;
    *) warn "Skipped — run 'team-claude init' later to set up CLAUDE.md" ;;
  esac
fi

if ! $DELIB_EXISTS; then
  echo ""
  echo -e "${YELLOW}⚠ No .deliberation/ directory found.${NC}"
  echo ""
  echo "  .deliberation/ stores decision records from ITM deliberation runs."
  echo "  DevGuard uses these to validate prompts against prior decisions."
  echo ""
  echo "  Options:"
  echo "  [1] Create empty .deliberation/ structure (no tokens)"
  echo "  [2] Skip — I'll run /kickoff to create it"
  echo ""
  ask "Choose [1/2]:"
  read -r DELIB_CHOICE

  case "${DELIB_CHOICE:-2}" in
    1)
      mkdir -p .deliberation/.example
      cat > .deliberation/README.md << 'DEOF'
# .deliberation/

This directory stores ITM deliberation decision records.

## Structure
Each feature gets a directory:
```
.deliberation/
  <feature-slug>/
    transcript.json     ← deliberation transcript
    decision.md         ← final decision record
    verification.json   ← verifier results
    state.json          ← workflow state
```

## Creating a deliberation
Run: /kickoff "your feature description"

DevGuard validates all prompts against decisions in this directory.
DEOF
      ok ".deliberation/ structure created"
      ;;
    *) warn "Skipped — run /kickoff to start your first deliberation" ;;
  esac
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ PromptShield installed${NC}"
echo ""
echo "  Device:  ${NAME}"
echo "  Mode:    ${MODE} ($([ "$MODE" = "max" ] && echo "Claude Max — local validation" || echo "API — gateway tracked"))"
echo "  OS:      ${OS_TYPE}"
echo ""
echo "  Commands:"
echo "  team-claude login    — verify your device ID"
echo "  team-claude chat     — start a tracked chat session"
echo "  team-claude status   — your usage vs quota"
echo "  team-claude init     — (re)generate CLAUDE.md"
echo ""
echo "  Dashboard: ${CYAN}${PAGES_URL}/mode-b.html${NC}"
echo ""
if [[ "$OS_TYPE" == "mac" || "$OS_TYPE" == "linux" || "$OS_TYPE" == "windows-bash" ]]; then
  echo -e "  ${YELLOW}Restart your terminal or run: source ~/.zshrc${NC}"
fi
echo ""
