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
