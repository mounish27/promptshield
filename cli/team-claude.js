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
