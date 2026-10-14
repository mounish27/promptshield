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
