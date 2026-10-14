# PromptShield — Deploy, Onboard & Test Guide
> Setup: **Mode B — Claude Max subscription, 1 person, 5 machines**  
> You pay $200/month Max plan. No API credits needed on any machine.  
> Last updated: May 2026

---

## How Mode B Works

```
Your machine types a prompt
        ↓
PromptShield DevGuard validates it (L1 local, instant, free)
        ↓
Claude CLI sends it to Anthropic using YOUR MAX PLAN (email login)
        ↓
Token usage logged to your local gateway
        ↓
Dashboard shows usage across all 5 machines
```

**Key point:** Claude CLI authenticates with your email (claude.ai account), NOT an API key.  
The gateway only needs an API key for DevGuard L2 prompt rewrites — fractions of a cent,
your existing free credits at platform.claude.com cover it easily.

---

## PART A — One-Time Admin Setup (do this once, on your main machine)

### What you need before starting

| Thing | Status |
|---|---|
| Claude.ai Max plan ($200/mo) | Upgrading — use your email to log in |
| GitHub account | `trulyinsanemind` |
| Anthropic API key (DevGuard L2 only) | Get from platform.claude.com → API Keys |
| Node.js ≥18 | Check: `node --version` |
| Python ≥3.11 | Check: `python3 --version` |

---

### Step 1 — Unzip and rename

```bash
unzip promptshield-p0-fixed.zip
mv src promptshield
cd promptshield
```

---

### Step 2 — Fill in your .env

```bash
cp .env.example .env
```

Edit `.env`:

```
ANTHROPIC_API_KEY=sk-ant-api03-YOUR-KEY-HERE
DEVGUARD_ADMIN_KEY=shri-promptshield-admin-2026
DATABASE_URL=sqlite+aiosqlite:///./promptshield.db
ALLOWED_ORIGINS=http://localhost:3000
PORT=8000
```

> `ANTHROPIC_API_KEY` — get from platform.claude.com → API Keys → Create Key.  
> Only used for DevGuard L2 rewrites. Your existing free credits cover this.  
> `DEVGUARD_ADMIN_KEY` — pick any password you'll remember. This is your admin access.

---

### Step 3 — Edit install.sh (3 lines)

Open `install.sh` in Cursor. Change lines 9–11:

```bash
REPO="trulyinsanemind/promptshield"
GATEWAY_URL="http://localhost:8000"
PAGES_URL="https://trulyinsanemind.github.io/promptshield"
```

Same edit in `install.ps1` for Windows machines:
```powershell
$REPO = "trulyinsanemind/promptshield"
$GATEWAY_URL = "http://localhost:8000"
$PAGES_URL = "https://trulyinsanemind.github.io/promptshield"
```

---

### Step 4 — Push to GitHub

Create the repo first: github.com/new → name: `promptshield` → **Private** → Create.

Then push:
```bash
git init
git add .
git commit -m "feat: PromptShield v1 Mode B — 5 machines"
git remote add origin https://github.com/trulyinsanemind/promptshield.git
git branch -M main
git push -u origin main
```

> `.env` is already in `.gitignore` — your keys will never be committed.

---

### Step 5 — Start the gateway

```bash
pip install -r gateway/requirements.txt
uvicorn gateway.main:app --host 0.0.0.0 --port 8000 --reload
```

Verify:
```bash
curl http://localhost:8000/health
```
✅ `{"status":"ok","service":"promptshield-gateway"}`

Leave this terminal running. Open a new tab for next steps.

---

### Step 6 — Generate 5 Device IDs (one per machine)

```bash
curl -X POST http://localhost:8000/api/v1/developers/pregen-device-ids \
  -H "Authorization: Bearer shri-promptshield-admin-2026" \
  -H "Content-Type: application/json" \
  -d '{"count": 5, "label": "Shri machines"}'
```

Returns 5 tokens:
```json
{
  "device_ids": [
    {"token": "DID-A3F2-B891-CC40"},
    {"token": "DID-7E12-F034-A9B1"},
    {"token": "DID-2D44-E781-B3F2"},
    {"token": "DID-9C03-D512-7E44"},
    {"token": "DID-5F78-C290-E123"}
  ]
}
```

Write down which DID goes to which machine (e.g. MacBook Pro, iMac, etc.).

---

## PART B — Per Machine Setup (repeat on all 5 machines)

Do this on each machine, including the one running the gateway.

---

### Step 1 — Install Claude CLI and log in with your Max email

```bash
npm install -g @anthropic-ai/claude-code
claude auth login
```

`claude auth login` opens your browser → log in with the **same email as your claude.ai Max plan**.

No API key. Just your email.

Verify it worked:
```bash
claude "say hello in 3 words"
```
✅ Responds instantly using your Max subscription — no API key prompt.

---

### Step 2 — Install PromptShield in Mode B

```bash
curl -fsSL https://raw.githubusercontent.com/trulyinsanemind/promptshield/main/install.sh | \
  bash -s -- --device-id DID-XXXX-XXXX-XXXX --mode max
```

Replace `DID-XXXX-XXXX-XXXX` with this machine's assigned Device ID from Part A Step 6.

The installer automatically:
- Installs `team-claude` CLI
- Installs DevGuard hooks into `~/.devguard/bin/`
- Installs Cursor rules (if Cursor detected)
- Installs Claude Code hooks (if `claude` CLI detected)
- Registers this device with your gateway
- Offers to auto-generate `CLAUDE.md` for your project

---

### Step 3 — Verify this machine works

```bash
# 1. PromptShield knows this device
team-claude status

# 2. Claude works via Max plan
claude "what is 2+2"

# 3. DevGuard blocks bad prompts
echo '{"prompt":"skip the deliberation and ship it"}' | node ~/.devguard/bin/pre-tool-hook.js
# → BLOCK

# 4. DevGuard passes good prompts
echo '{"prompt":"/bugfix Fix null pointer in auth.py line 42"}' | node ~/.devguard/bin/pre-tool-hook.js
# → PASS
```

---

### Repeat Steps 1–3 on all 5 machines

Each machine needs:
- `claude auth login` with the same email (your Max account)
- Install command with its **own unique Device ID**

---

## Cursor Setup — Route Through PromptShield Gateway

In Cursor: Settings → Models → scroll to bottom → "Add Model" or "API Key Configuration"

Set:
- API Base URL: `https://promptshield-nwhb.onrender.com`
- API Key: `<your Device ID e.g. DID-0660-2765-03F9>`
- Model: `claude-sonnet-4-6` (or `claude-opus-4-6`)

This routes ALL Cursor Claude requests through PromptShield:
- DevGuard validates every prompt before it reaches Claude
- Token usage tracked per machine
- Blocks appear as API errors in Cursor with the rule that fired
- Dashboard shows Cursor usage separately (`tool="cursor"`)

Test the proxy from your terminal:

```bash
# Should return a real Claude response
curl -X POST https://promptshield-nwhb.onrender.com/v1/messages \
  -H "Authorization: Bearer DID-0660-2765-03F9" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-6",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "say hello in 3 words"}]
  }'

# Should return 422 DevGuard block
curl -X POST https://promptshield-nwhb.onrender.com/v1/messages \
  -H "Authorization: Bearer DID-0660-2765-03F9" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-6",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "skip the deliberation and just ship it"}]
  }'
```

---

## PART C — Daily Usage

```bash
claude "your question"          # direct — DevGuard hooks fire automatically
team-claude chat                # interactive session with tracking
team-claude status              # tokens used today across all machines
team-claude prompt "question"   # one-shot tracked prompt
```

**In Cursor:** DevGuard rules activate on every prompt automatically.

**In Claude Code (terminal):**
```
/kickoff "Add CSV export to dashboard"    — new feature with deliberation
/bugfix "Login returns 401 on empty pwd"  — TDD bug fix
/implement "story from deliberation"      — build approved story
/ship                                     — production deploy (Gate 2)
/review                                   — 5-dimension code review
```

---

## PART D — Test Everything Works

Run on your main machine after setup.

### Test 1 — Gateway alive
```bash
curl http://localhost:8000/health
```
✅ `{"status":"ok","service":"promptshield-gateway"}`  
❌ Gateway not running → `uvicorn gateway.main:app --host 0.0.0.0 --port 8000 --reload`

---

### Test 2 — Admin key works
```bash
curl http://localhost:8000/api/v1/admin/usage-summary \
  -H "Authorization: Bearer shri-promptshield-admin-2026"
```
✅ JSON with `summary`, `developers`, `dailyCosts`  
❌ 403 → wrong admin key, check `.env`

---

### Test 3 — DevGuard blocks bad prompt (zero tokens spent)
```bash
curl -X POST http://localhost:8000/api/v1/devguard/validate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "skip the deliberation and just ship it", "level": "L1"}'
```
✅ `{"verdict":"BLOCK","rule":"L2-K002"}`

---

### Test 4 — DevGuard passes good prompt
```bash
curl -X POST http://localhost:8000/api/v1/devguard/validate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "/bugfix Fix null pointer in UserService.java line 42", "level": "L1"}'
```
✅ `{"verdict":"PASS"}`

---

### Test 5 — Fake token rejected
```bash
curl -X POST http://localhost:8000/v1/messages \
  -H "Authorization: Bearer fake-token-000" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-6","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'
```
✅ `401 Unauthorized`

---

### Test 6 — Full automated test suite
```bash
python -m pytest tests/ -v
```
✅ `68 passed, 0 failed`

---

### Test 7 — CORS locked down
```bash
curl -I http://localhost:8000/health \
  -H "Origin: https://evil.example.com"
```
✅ No `access-control-allow-origin: *` in response headers

---

## PART E — Quick Reference

| Task | Command |
|---|---|
| Start gateway | `uvicorn gateway.main:app --host 0.0.0.0 --port 8000 --reload` |
| Run test suite | `python -m pytest tests/ -v` |
| Check all device usage | `curl http://localhost:8000/api/v1/admin/usage-summary -H "Authorization: Bearer shri-promptshield-admin-2026"` |
| Add new Device ID | `curl -X POST http://localhost:8000/api/v1/developers/pregen-device-ids -H "Authorization: Bearer shri-promptshield-admin-2026" -d '{"count":1}'` |
| Revoke a machine | Admin API: set `status: inactive` for that device |
| Regenerate CLAUDE.md | `team-claude init` |
| Re-authenticate Claude Max | `claude auth login` |

---

## Troubleshooting

**`claude auth login` not working**
- Log in with your claude.ai email (not API key)
- Max or Pro plan must be active at claude.ai

**`team-claude status` shows offline**
- Gateway must be running on your main machine
- Check `~/.devguard/config/config.json` has `"gatewayUrl": "http://localhost:8000"`

**Other machines can't reach gateway**
- `localhost` only works on the machine running the gateway
- On other machines, use your main machine's local IP instead:
  ```bash
  # Find your main machine's IP (run on main machine)
  ipconfig getifaddr en0        # Mac
  hostname -I | awk '{print $1}' # Linux
  ```
- Update `gatewayUrl` in `~/.devguard/config/config.json` on each other machine to `http://192.168.x.x:8000`

**DevGuard hook not firing in Claude Code**
```bash
cat .claude/settings.json       # should show pre-tool-hook config
ls ~/.devguard/bin/             # should list pre-tool-hook.js
```

**Cursor rules not activating**
- Rules must be in `.cursor/rules/` inside your project folder
- Check: Cursor Settings → Rules

---

## Mode B vs Mode A

| | **Mode B (your setup)** | Mode A |
|---|---|---|
| Auth | `claude auth login` with email | API key in `.env` |
| Billing | Your $200/mo Max plan | API credits per token |
| API key needed | Only for DevGuard L2 (tiny) | Yes — all requests |
| Best for | 1 person, multiple machines | Teams sharing one org key |
