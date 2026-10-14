# PromptShield

**AI developer governance platform.** Controls who can access your Claude API key, validates every prompt before it reaches Claude, tracks token usage per device, and reports everything to a live admin dashboard.

Works on **Mac, Linux, and Windows** (PowerShell + WSL/Git Bash).

---

## How it works

```
Developer types a prompt on any device (Mac / Windows / Linux)
              ↓
PromptShield DevGuard validates + rewrites the prompt
  → BLOCK:    returns corrected prompt — 0 tokens spent
  → REWRITE:  improves weak prompt before sending
  → PASS:     forwards to Claude API (key stays on your server)
              ↓
Token usage logged per device
              ↓
Your dashboard at YOUR_ORG.github.io/promptshield updates every 5 min
```

---

## Part 1 — Admin: First-Time Setup

### Prerequisites

| Tool | Mac | Windows | Linux |
|------|-----|---------|-------|
| Node.js ≥18 | `brew install node` | `winget install OpenJS.NodeJS.LTS` | `sudo apt install nodejs` |
| Git | `brew install git` | `winget install Git.Git` | `sudo apt install git` |
| Python ≥3.11 | `brew install python` | `winget install Python.Python.3.11` | `sudo apt install python3` |
| Claude Code CLI | See below | See below | See below |

### Install Claude Code CLI

**Mac / Linux:**
```bash
npm install -g @anthropic-ai/claude-code
claude --version
claude auth login   # login with your Anthropic account
```

**Windows (PowerShell):**
```powershell
npm install -g @anthropic-ai/claude-code
claude --version
claude auth login
```

**Windows (WSL / Git Bash):**
```bash
npm install -g @anthropic-ai/claude-code
claude auth login
```

> Claude Code requires Node ≥18 and an Anthropic account (Pro or Max plan for CLI usage, or API credits).

---

### Step 1 — Create the GitHub repo

```bash
gh repo create promptshield --private
git clone https://github.com/YOUR_ORG/promptshield
cd promptshield
```

Or unzip the downloaded package:
```bash
unzip promptshield.zip && cd promptshield
git remote add origin https://github.com/YOUR_ORG/promptshield
```

---

### Step 2 — Configure environment

```bash
cp .env.example .env
```

Edit `.env`:
```
ANTHROPIC_API_KEY=sk-ant-api03-...      # your Claude API key
DEVGUARD_ADMIN_KEY=<openssl rand -hex 32>
DATABASE_URL=sqlite+aiosqlite:///./promptshield.db
```

**Windows (PowerShell):**
```powershell
Copy-Item .env.example .env
# Edit .env in Notepad: notepad .env
```

---

### Step 3 — Start the gateway

```bash
pip install -r gateway/requirements.txt
uvicorn gateway.main:app --host 0.0.0.0 --port 8000 --reload
```

**Windows:**
```powershell
pip install -r gateway/requirements.txt
python -m uvicorn gateway.main:app --host 0.0.0.0 --port 8000 --reload
```

Verify: `curl http://localhost:8000/health`

---

### Step 4 — Update installer URLs

Edit lines 6–8 in `install.sh` AND `install.ps1`:
```
REPO="your-org/promptshield"
GATEWAY_URL="https://your-gateway.com"
PAGES_URL="https://your-org.github.io/promptshield"
```

---

### Step 5 — Pre-generate Device IDs (Mode B)

Instead of generating tokens one by one, pre-generate a batch of Device IDs.
Developers pick one and input it during install.

**Via admin dashboard:**
Mode B → My Devices → "Generate 4 Device IDs" → copy and distribute

**Via terminal:**
```bash
curl -X POST http://localhost:8000/api/v1/developers/pregen-device-ids \
  -H "Authorization: Bearer YOUR_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"count": 4, "label": "Shri personal devices"}'
```

Returns:
```json
{
  "device_ids": [
    {"token": "DID-A3F2-B891-CC40", "label": "Shri personal devices"},
    {"token": "DID-7E12-F034-A9B1", "label": "Shri personal devices"},
    {"token": "DID-2D44-E781-B3F2", "label": "Shri personal devices"},
    {"token": "DID-9C03-D512-7E44", "label": "Shri personal devices"}
  ]
}
```

Assign one Device ID per device. Each activates on first install.

---

### Step 6 — Deploy GitHub Pages

```bash
git checkout --orphan gh-pages
git rm -rf .
echo "<html><body>Setting up...</body></html>" > index.html
git add index.html && git commit -m "init" && git push origin gh-pages
git checkout main
```

GitHub repo → Settings → Pages → Branch: `gh-pages` → `/root` → Save

Add GitHub Secrets:
- `ANTHROPIC_API_KEY`
- `DEVGUARD_ADMIN_KEY`
- `GATEWAY_URL`

Push everything:
```bash
git add . && git commit -m "feat: PromptShield v1" && git push origin main
```

---

## Part 2 — Developer Install (any device)

### Mac / Linux — one command

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/promptshield/main/install.sh | bash
```

The installer will ask for:
1. Your **Device ID** (looks like `DID-XXXX-XXXX-XXXX` — get it from your admin)
2. Your **device name** (auto-detected from hostname, press Enter to accept)

Silent install with args:
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/promptshield/main/install.sh | \
  bash -s -- --device-id DID-XXXX-XXXX-XXXX --name "MacBook Pro Studio"
```

Claude Max mode (local validation, no gateway):
```bash
curl -fsSL .../install.sh | bash -s -- --device-id DID-XXXX-XXXX-XXXX --mode max
```

---

### Windows — PowerShell

Open PowerShell (as Administrator recommended):
```powershell
iwr -useb https://raw.githubusercontent.com/YOUR_ORG/promptshield/main/install.ps1 | iex
```

With args:
```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/YOUR_ORG/promptshield/main/install.ps1 -UseBasicParsing).Content)) -DeviceId "DID-XXXX-XXXX-XXXX" -Name "My Windows PC"
```

If PowerShell execution policy blocks it:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# Then re-run the install command above
```

---

### Windows — WSL or Git Bash

Same as Mac/Linux:
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/promptshield/main/install.sh | bash
```

---

### What happens during install

1. Checks Node.js ≥18 (tells you exactly how to install if missing)
2. Asks for Device ID and device name
3. Installs `team-claude` CLI globally
4. Downloads DevGuard hooks to `~/.devguard/bin/`
5. Installs Cursor rules (if `.cursor/` folder detected)
6. Installs Claude Code hooks (if `claude` CLI detected)
7. Syncs `CLAUDE.md` from gateway
8. **Checks for empty CLAUDE.md** → offers to:
   - Auto-generate using Claude (scans your project, ~500 tokens)
   - Copy starter template (no tokens, fill in manually)
   - Skip
9. **Checks for empty `.deliberation/`** → offers to:
   - Create empty structure
   - Skip (run `/kickoff` later)
10. Registers device with gateway

---

## Part 3 — After Install: First Steps

### Verify everything works

```bash
# Check CLI
team-claude status

# Check CLAUDE.md was created
cat CLAUDE.md | head -10

# Check hooks installed
cat ~/.devguard/config/config.json

# Test DevGuard (should show PASS)
echo '{"prompt":"/kickoff \"Add CSV export to dashboard\""}' | node ~/.devguard/bin/pre-tool-hook.js

# Test DevGuard (should BLOCK + rewrite)
echo '{"prompt":"fix the bug and clean up while you are there"}' | node ~/.devguard/bin/pre-tool-hook.js
```

**Windows:**
```powershell
team-claude status
Get-Content "$env:USERPROFILE\.devguard\config\config.json"
```

---

### If CLAUDE.md is empty or missing

Run any time:
```bash
team-claude init
# Scans project, generates CLAUDE.md using Claude Haiku (~500 tokens)
```

Or copy the template manually:
```bash
cp ~/.devguard/templates/CLAUDE.md.template ./CLAUDE.md
# Then edit it with your project details
```

---

### If .deliberation/ is missing

Run your first feature:
```
/kickoff "Your first feature description"
```

This runs the 4-role deliberation and creates `.deliberation/<slug>/` automatically.

---

## Part 4 — Daily Developer Usage

```bash
team-claude login     # verify device ID
team-claude chat      # interactive chat (tracked + validated)
team-claude status    # tokens used today vs quota
team-claude prompt "your message"  # one-shot prompt
team-claude init      # regenerate CLAUDE.md
```

In Cursor: DevGuard rules activate automatically on every prompt.
In Claude Code: Slash commands available (`/kickoff`, `/bugfix`, `/implement`, `/ship`, `/devguard`).

---

## Part 5 — Device ID Management

### Admin pre-generates IDs (recommended)

```bash
# Generate 4 device IDs at once
curl -X POST http://YOUR_GATEWAY/api/v1/developers/pregen-device-ids \
  -H "Authorization: Bearer YOUR_ADMIN_KEY" \
  -d '{"count": 4, "label": "My personal devices"}'
```

Distribute one `DID-XXXX-XXXX-XXXX` per device. They activate on first install.

### Check device status

```bash
curl http://YOUR_GATEWAY/api/v1/developers/device-ids \
  -H "Authorization: Bearer YOUR_ADMIN_KEY"
```

Returns: name, status (pending/active/inactive), last seen, token usage per device.

### Revoke a device

Admin dashboard → Mode B → My Devices → Revoke

Or via API:
```bash
curl -X PATCH http://YOUR_GATEWAY/api/v1/developers/DEVICE_UUID \
  -H "Authorization: Bearer YOUR_ADMIN_KEY" \
  -d '{"status": "inactive"}'
```

Device gets 401 on next request. Other devices unaffected.

---

## Part 6 — Production Deploy

### Linux server (systemd)

```bash
sudo tee /etc/systemd/system/promptshield.service << EOF
[Unit]
Description=PromptShield Gateway
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/promptshield
EnvironmentFile=/home/ubuntu/promptshield/.env
ExecStart=/usr/local/bin/uvicorn gateway.main:app --host 0.0.0.0 --port 8000 --workers 4
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable promptshield && sudo systemctl start promptshield
```

### Windows Server

```powershell
# Install as Windows Service using NSSM
winget install NSSM
nssm install PromptShield "python" "-m uvicorn gateway.main:app --host 0.0.0.0 --port 8000"
nssm set PromptShield AppDirectory "C:\promptshield"
nssm start PromptShield
```

### Replit / Railway / Render

Set env vars `ANTHROPIC_API_KEY` and `DEVGUARD_ADMIN_KEY` in dashboard.
Start command: `uvicorn gateway.main:app --host 0.0.0.0 --port $PORT`

---

## Troubleshooting

**"Node.js not found" on Windows**
```powershell
winget install OpenJS.NodeJS.LTS
# Close and reopen PowerShell, then re-run installer
```

**"curl not found" on Windows**
Use PowerShell installer instead (`install.ps1`), or install curl:
```powershell
winget install cURL.cURL
```

**Device ID rejected (401)**
```bash
# Check gateway is running
curl http://YOUR_GATEWAY/health

# Check your device ID has no extra spaces
cat ~/.devguard/config/config.json

# Re-register
team-claude login
```

**CLAUDE.md missing after install**
```bash
team-claude init   # auto-generates from project
# or
cp ~/.devguard/templates/CLAUDE.md.template ./CLAUDE.md
```

**Cursor rules not activating**
- Must be in `.cursor/rules/` inside your project folder
- Must have `.mdc` extension
- Check: Cursor Settings → Rules

**DevGuard hook not firing in Claude Code**
```bash
cat .claude/settings.json   # should show pre-tool-hook config
ls ~/.devguard/bin/         # should list pre-tool-hook.js
```

**Windows: "execution of scripts is disabled"**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Part 7 — Claude Code CLI: Full Usage Guide

### What Claude Code is

Claude Code is Anthropic's terminal-based AI coding assistant. You type slash commands and natural language in your terminal, and Claude Code reads your codebase, writes code, runs tests, and explains decisions — all without leaving the terminal.

With PromptShield installed, every Claude Code session is automatically:
- Validated by DevGuard before any tool runs
- Injected with your CLAUDE.md project context
- Tracked for token usage per device
- Logged for review on your dashboard

---

### Installing Claude Code CLI

**Mac:**
```bash
npm install -g @anthropic-ai/claude-code
```

**Windows (PowerShell):**
```powershell
npm install -g @anthropic-ai/claude-code
```

**Linux:**
```bash
npm install -g @anthropic-ai/claude-code
```

Verify: `claude --version`

---

### Authenticating Claude Code

**With a claude.ai subscription (Pro or Max):**
```bash
claude auth login
# Opens browser — log in with your Anthropic account
# Your Max/Pro usage covers Claude Code sessions
```

**With API credits (PromptShield gateway mode):**
```bash
# Don't run claude auth login for API mode
# Instead configure team-claude to route through gateway:
team-claude config set gatewayUrl https://your-gateway.com
team-claude config set developerToken DID-XXXX-XXXX-XXXX
```

---

### Starting Claude Code

```bash
# Navigate to your project
cd ~/projects/my-app

# Start Claude Code
claude

# Claude Code reads CLAUDE.md automatically on start
# PromptShield DevGuard hooks activate automatically
```

---

### PromptShield slash commands in Claude Code

Once PromptShield is installed, these slash commands are available:

```bash
# Start a new feature (runs deliberation first)
/kickoff "Add CSV export to the usage dashboard with date range filter"

# Fix a bug (TDD — failing test first)
/bugfix "Overtime calculation returns negative when hours equals 8"

# Build an approved story (Gate 1 must be merged)
/implement specs/shift-swap/stories/001-approve-swap.md

# Ship to production (Gate 2 required)
/ship #42

# Validate your prompt before submitting
/devguard "your prompt here"

# Run code review after coding
/review
/review specs/auth/stories/001-login.md

# Enhance an existing feature
/enhance "Add team filter dropdown to the dashboard"

# Process a BRD
/brd docs/requirements.md
```

---

### What happens on every Claude Code prompt

1. You type a prompt or slash command
2. `pre-tool-hook.js` fires (PreToolUse hook — before Claude does anything)
3. DevGuard checks for anti-patterns and gate bypasses
4. If BLOCK: corrected prompt shown, Claude Code stops
5. If PASS: CLAUDE.md context injected, forwarded to Claude
6. Claude responds
7. `usage-reporter.js` fires (PostToolUse hook — after Claude responds)
8. Token count, cost, DevGuard verdict logged to your dashboard

---

### After coding: running the review

At the end of every `/implement` or `/bugfix`, Claude Code asks:

```
┌─────────────────────────────────────────────────────────────┐
│  ✓ Implementation complete                                   │
│                                                              │
│  Do you want to run a PromptShield code review?             │
│  [Y] Run review now    [N] Skip                             │
└─────────────────────────────────────────────────────────────┘
```

Type `Y` to run `/review` automatically. The review:
- Checks 5 dimensions: deliberation alignment, acceptance criteria, code quality, security, test coverage
- Saves the report to `.promptshield/review-<timestamp>.md` in your project
- Logs the report to the gateway — visible in your dashboard under Code Reviews
- Prints a summary with any blocking issues

Run manually any time:
```bash
/review
/review specs/auth/stories/001-login.md
```

---

### Viewing review reports

```bash
# List all reviews for this project
ls .promptshield/

# Read a specific review
cat .promptshield/review-20260519-143022.md

# See all reviews across all devices on the dashboard
open https://YOUR_ORG.github.io/promptshield/mode-b.html
# → My Activity tab → Reviews section
```

---

### team-claude CLI full command reference

```bash
team-claude login                    # verify your Device ID with the gateway
team-claude chat                     # interactive chat session (tracked)
team-claude prompt "your message"    # single prompt, returns response
team-claude status                   # tokens today/month, quota, DevGuard stats
team-claude init                     # generate or regenerate CLAUDE.md
team-claude sync                     # sync latest CLAUDE.md from gateway
team-claude config get gatewayUrl    # view config value
team-claude config set key value     # set config value
```

---

### Common Claude Code workflows with PromptShield

**Starting a new feature from scratch:**
```bash
cd ~/projects/my-app
claude
/kickoff "User can export usage data as CSV with date range filter"
# Runs 4-role deliberation → Gate 1 PR opens → you review → approve
# Then:
/implement specs/csv-export/stories/001-export-button.md
# At end: "Do you want to run a review?" → Y
```

**Fixing a bug:**
```bash
claude
/bugfix "CSV export fails with empty date range — TypeError on line 47 of ExportService"
# Writes failing test first → fixes → full suite → asks for review
```

**Checking your work before committing:**
```bash
/review
# Reviews everything in git diff, saves report, logs to dashboard
```

**If DevGuard blocks your prompt:**
```bash
# You type:
/bugfix "Fix auth and also clean up the module while we're at it"

# DevGuard responds:
# ┌─ PromptShield BLOCK [L1-007]
# │ Problem: Scope creep — 'while we're at it'
# │
# │ ✓ Corrected prompt:
# │   /bugfix "Auth null pointer on login — UserService.validate() line 23"
# └────────────────────────────────────────────────────────────

# Use the corrected prompt and continue
```

---

## Examples — New Project vs Existing Project

### Scenario A — Brand new project

You just created a new repo and want PromptShield from day one.

```
Terminal 1: Start the gateway (runs in background)
─────────────────────────────────────────────────
cd /usr/github/standard-repo/promptshield
uvicorn gateway.main:app --host 0.0.0.0 --port 8000

Terminal 2: Your new project
─────────────────────────────────────────────────
mkdir /usr/github/my-new-app
cd /usr/github/my-new-app
git init

# Install PromptShield (paste your Device ID when asked)
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/promptshield/main/install.sh | bash

# Open Claude Code — session-start checker runs automatically
claude
```

**What you see when claude opens:**

```
⬡ PromptShield — Project setup check
  All files → .promptshield/   One gitignore entry covers everything.
  Project: /usr/github/my-new-app

┌─ PromptShield: First time in this project ─────────────────────
│
│  PromptShield will create ONE folder in your project:
│  .promptshield/
│
│  Contains: CLAUDE.md, deliberation records, specs, hooks, reviews.
│  Add ONE line to .gitignore and nothing is ever committed:
│  .promptshield/
│
│  [1] Create .promptshield/ and set up this project
│  [2] Skip
└────────────────────────────────────────────────────────────────
? Choose [1/2]: 1
✓ .promptshield/ structure created

┌─ PromptShield: CLAUDE.md missing ─────────────────────────────
│  [1] Auto-generate using Claude Haiku (~500 tokens) — recommended
│  [2] Copy starter template — fill in manually
│  [3] Skip for now
└────────────────────────────────────────────────────────────────
? Choose [1/2/3]: 1

  Scanning project...
  Calling Claude Haiku to generate CLAUDE.md (~500 tokens)...
✓ .promptshield/CLAUDE.md generated (1,240 chars)

  Preview:
  # CLAUDE.md — my-new-app
  Stack: (detected from package.json)
  ...

┌─ PromptShield: No deliberation records ───────────────────────
│  [1] Create empty structure — I'll populate via /kickoff
│  [2] Skip — created automatically when I run /kickoff
└────────────────────────────────────────────────────────────────
? Choose [1/2]: 1
✓ .promptshield/deliberation/ structure created

✓ .promptshield/specs/ structure created
✓ .promptshield/claude-hooks/ installed

┌─ PromptShield: .gitignore not configured ──────────────────────
│  Add ONE line — nothing PromptShield creates is ever committed:
│  .promptshield/
│
│  [1] Add to global ~/.gitignore_global (covers ALL repos)
│  [2] Add to this project's .gitignore only
│  [3] Skip
└────────────────────────────────────────────────────────────────
? Choose [1/2/3]: 1
✓ ~/.gitignore_global updated — .promptshield/ ignored in all repos

✓ PromptShield ready — all files in .promptshield/

  .promptshield/ structure:
  ├── CLAUDE.md         project context
  ├── deliberation/     decision records (created by /kickoff)
  ├── specs/            feature specs (created by /kickoff)
  ├── claude-hooks/     Claude Code settings + commands
  ├── cursor-rules/     Cursor .mdc rules
  └── reviews/          code review reports
```

**Now start your first feature:**

```
/kickoff "User can sign up with email and password, receives confirmation email"
```

PromptShield runs 4-role deliberation, creates `.promptshield/deliberation/signup/` and `.promptshield/specs/signup/` automatically. Gate 1 PR opens for your review.

**Your project now looks like:**

```
/usr/github/my-new-app/
├── .promptshield/          ← everything PromptShield (gitignored)
│   ├── CLAUDE.md
│   ├── deliberation/
│   │   └── signup/
│   │       ├── decision.md
│   │       ├── transcript.json
│   │       └── verification.json
│   ├── specs/
│   │   └── signup/
│   │       ├── brief.md
│   │       └── stories/001-email-signup.md
│   ├── claude-hooks/
│   │   ├── settings.json
│   │   └── commands/
│   └── reviews/
├── src/                    ← your actual code (committed normally)
├── package.json
└── .gitignore              ← contains: .promptshield/
```

---

### Scenario B — Existing project (already has code)

You have a project that's been running for months. You want to add PromptShield governance without changing anything that's committed.

```
# Go to your existing project
cd /usr/github/certainti

# Your project already has:
# ✓ src/, tests/, package.json, README.md
# ✓ Existing git history
# ✗ No CLAUDE.md yet
# ✗ No deliberation records

# Install PromptShield
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/promptshield/main/install.sh | bash

# Open Claude Code
claude
```

**What you see:**

```
⬡ PromptShield — Project setup check
  Project: /usr/github/certainti

┌─ PromptShield: First time in this project ─────────────────────
│  [1] Create .promptshield/ and set up this project
│  [2] Skip
└────────────────────────────────────────────────────────────────
? Choose [1/2]: 1
✓ .promptshield/ structure created

┌─ PromptShield: CLAUDE.md missing ─────────────────────────────
│  [1] Auto-generate using Claude Haiku (~500 tokens)
│  [2] Copy starter template
│  [3] Skip
└────────────────────────────────────────────────────────────────
? Choose [1/2/3]: 1

  Scanning project...
  Found: package.json (certainti, FastAPI + React stack)
  Found: README.md (15 lines of context)
  Calling Claude Haiku...
✓ .promptshield/CLAUDE.md generated

  Preview:
  # CLAUDE.md — Certainti
  Stack: FastAPI, React, PostgreSQL, Claude API
  Description: AI compliance and data privacy training platform
  ...

┌─ PromptShield: No deliberation records ───────────────────────
│  This looks like an existing project.
│  [1] Create empty structure — I'll add records as I work
│  [2] Run /kickoff now to start next feature with deliberation
│  [3] Skip — my project doesn't use deliberation yet
└────────────────────────────────────────────────────────────────
? Choose [1/2/3]: 2
✓ Got it — type /kickoff "your feature" to start deliberation.

✓ .promptshield/specs/ structure created
✓ .promptshield/claude-hooks/ installed
✓ ~/.gitignore_global updated

✓ PromptShield ready
```

**Nothing in your git history changed.** Your existing commits, branches, and code are untouched. The only new thing is `.promptshield/` which is gitignored.

**Now work on your next feature using your existing codebase:**

```
# DevGuard now validates every prompt
/kickoff "Add voice calibration scoring to the sales call analysis module"

# PromptShield creates:
# .promptshield/deliberation/voice-calibration/decision.md
# .promptshield/specs/voice-calibration/stories/

# Implement after Gate 1 approval
/implement .promptshield/specs/voice-calibration/stories/001-vad-scoring.md

# At end of implementation — Claude Code asks:
# "Do you want to run a PromptShield review?"
# → Y
# Report saved to .promptshield/reviews/review-20260519-143022.md
```

**Your existing project now looks like:**

```
/usr/github/certainti/
├── .promptshield/          ← gitignored, never committed
│   ├── CLAUDE.md               auto-generated from your codebase
│   ├── deliberation/
│   │   └── voice-calibration/
│   │       └── decision.md
│   ├── specs/
│   │   └── voice-calibration/
│   ├── claude-hooks/
│   └── reviews/
├── src/                    ← your existing code, unchanged
├── tests/                  ← your existing tests, unchanged
├── package.json            ← unchanged
└── .gitignore              ← contains: .promptshield/
```

---

### Scenario C — Multiple projects, same device

You work on several projects. Each gets its own `.promptshield/` with its own CLAUDE.md and deliberation records.

```
# Project 1 — new feature
cd /usr/github/certainti
claude
# PromptShield loads .promptshield/CLAUDE.md for Certainti
# DevGuard knows about Certainti's deliberation decisions

# Project 2 — bug fix
cd /usr/github/promptshield
claude
# PromptShield loads .promptshield/CLAUDE.md for PromptShield
# DevGuard knows about PromptShield's deliberation decisions
```

Each project is completely isolated. Switching projects means Claude Code automatically gets the right context for that project.

---

### What happens on every subsequent session (after first setup)

Once `.promptshield/` exists, the session check is instant and silent:

```
# Open Claude Code in your project
claude

# PromptShield checks in <1 second:
# ✓ .promptshield/CLAUDE.md exists
# ✓ .promptshield/deliberation/ exists
# ✓ .promptshield/claude-hooks/ exists
# (all checks pass — no prompts shown)

# Claude Code starts, CLAUDE.md context injected automatically
# You type your first prompt:

/bugfix "Overtime calculation returns negative when hours equals 8"

# DevGuard validates instantly — PASS
# CLAUDE.md context injected into Claude's system prompt
# Claude Code runs with full project context from session start
```

The check re-runs if:
- You switch to a different project directory
- More than 1 hour has passed since last check
- You run `team-claude check` manually

---

### Quick reference — commands after setup

```bash
# Check setup status for current project
team-claude check

# Regenerate CLAUDE.md (if project has changed significantly)
team-claude init

# Sync CLAUDE.md from gateway to this device
team-claude sync

# View your usage
team-claude status

# Start a governed chat session
team-claude chat

# Force re-run the session checker right now
team-claude check --force
```

---

### The single gitignore rule

Add this once globally and never think about it again:

```bash
# Run this once on any machine
echo ".promptshield/" >> ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global
```

Every project on every machine — `.promptshield/` is always ignored. No per-project setup needed.
#   p r o m p t s h i e l d  
 