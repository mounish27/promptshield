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
