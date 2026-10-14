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
