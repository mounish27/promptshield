# PromptShield — Go-Live Guide
> How to push to GitHub, deploy the gateway, onboard your developer, and verify everything works.  
> Written for: **you (admin)** and **your developer**.

---

## PART 1 — YOU (ADMIN): Push to GitHub

### Step 1 — Rename the folder first
After unzipping `promptshield-p0-fixed.zip`, rename `src` → `promptshield`:
```bash
mv src promptshield
```

### Step 2 — Create a private GitHub repo
1. Go to https://github.com/new
2. Name it `promptshield`
3. Set to **Private**
4. Do NOT initialize with README (you already have one)
5. Click **Create repository**

### Step 3 — Push the code
```bash
cd promptshield
git init
git add .
git commit -m "feat: PromptShield MVP with P0 security fixes and 68 tests"
git branch -M main
git remote add origin https://github.com/YOUR_ORG/promptshield.git
git push -u origin main
```
Replace `YOUR_ORG` with your GitHub username or org name.

### Step 4 — Add GitHub Secrets (for CI)
Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these three:

| Secret name | Value |
|---|---|
| `ANTHROPIC_API_KEY` | Your `sk-ant-...` key from console.anthropic.com |
| `DEVGUARD_ADMIN_KEY` | Run `openssl rand -hex 32` in terminal — paste result |
| `GATEWAY_URL` | Your server URL (e.g. `https://your-server.com`) — add after deploy |

---

## PART 2 — YOU (ADMIN): Deploy the Gateway

Pick **one** option. Replit is fastest for testing.

---

### Option A — Replit (fastest, ~5 min)

1. Go to https://replit.com → **Create Repl** → **Import from GitHub**
2. Paste your repo URL
3. In Replit **Secrets** (padlock icon), add:
   - `ANTHROPIC_API_KEY` = your key
   - `DEVGUARD_ADMIN_KEY` = your 32-char hex key
   - `ALLOWED_ORIGINS` = `https://your-replit-url.replit.app` *(set after first run)*
4. Set run command: `cd gateway && uvicorn main:app --host 0.0.0.0 --port 8000`
5. Click **Run**
6. Copy the public URL — this is your `GATEWAY_URL`

**Test it:**
```bash
curl https://YOUR-REPLIT-URL.replit.app/health
# Expected: {"status":"ok","service":"promptshield-gateway"}
```

---

### Option B — Linux server (EC2, DigitalOcean, Hetzner)

```bash
# On your server — one-time setup
git clone https://github.com/YOUR_ORG/promptshield
cd promptshield
cp .env.example .env
nano .env   # fill in ANTHROPIC_API_KEY and DEVGUARD_ADMIN_KEY

pip install -r gateway/requirements.txt --break-system-packages

# Run as a systemd service (stays alive after reboot)
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

sudo systemctl enable promptshield
sudo systemctl start promptshield
sudo systemctl status promptshield   # should say: Active: active (running)
```

**Test it:**
```bash
curl http://YOUR-SERVER-IP:8000/health
# Expected: {"status":"ok","service":"promptshield-gateway"}
```

---

### Option C — Railway / Render (1-click cloud)

1. Go to https://railway.app or https://render.com
2. Connect your GitHub repo
3. Set environment variables: `ANTHROPIC_API_KEY`, `DEVGUARD_ADMIN_KEY`, `ALLOWED_ORIGINS`
4. Start command: `uvicorn gateway.main:app --host 0.0.0.0 --port $PORT`
5. Deploy — get your public URL

---

## PART 3 — YOU (ADMIN): Create Your Developer's Token

Once the gateway is running, create a token for your developer. Run this from your machine:

```bash
curl -X POST https://YOUR-GATEWAY-URL/api/v1/developers/create \
  -H "Authorization: Bearer YOUR_DEVGUARD_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Developer Name",
    "email": "dev@yourcompany.com",
    "team": "engineering"
  }'
```

You'll get back:
```json
{
  "ok": true,
  "token": "abc123xyz...",
  "id": "uuid-here"
}
```

**Save the token** — you'll send it to your developer. It won't be shown again.

---

## PART 4 — MESSAGE TO SEND YOUR DEVELOPER

Copy and send this exactly (fill in the blanks):

---

**Subject: PromptShield access — Claude CLI setup**

Hey,

We're using PromptShield to manage our shared Claude access. Here's how to set up in ~5 minutes.

**Your personal token:** `[PASTE TOKEN HERE]`
**Gateway URL:** `[PASTE GATEWAY URL HERE]`

**Install (run this once):**
```bash
# Install the team-claude CLI
cd [PATH TO PROMPTSHIELD REPO]/cli
npm install -g .

# Log in with your token
team-claude login [YOUR TOKEN] --gateway [GATEWAY URL]
```

**Daily usage:**
```bash
team-claude chat              # starts a tracked Claude session
team-claude status            # see your token usage vs quota
team-claude prompt "message"  # one-shot prompt
```

**Claude Code (if you use it):**
```bash
# From inside your project folder
team-claude init              # installs DevGuard hooks + syncs CLAUDE.md
claude                        # Claude Code now routes through PromptShield
```

**Your limits:** 500,000 tokens/day, 5,000,000 tokens/month.

If you get a 401 error, your token may have expired — message me.

---

## PART 5 — TESTING: Verify Everything Works

Run these checks in order. Each one is a pass/fail.

### Test 1 — Gateway health
```bash
curl https://YOUR-GATEWAY-URL/health
```
✅ Pass: `{"status":"ok","service":"promptshield-gateway"}`  
❌ Fail: Connection refused → gateway not running. Check `systemctl status promptshield`

---

### Test 2 — Admin key works
```bash
curl https://YOUR-GATEWAY-URL/api/v1/admin/usage-summary \
  -H "Authorization: Bearer YOUR_DEVGUARD_ADMIN_KEY"
```
✅ Pass: Returns JSON with `"developers": [...]`  
❌ Fail: 403 → wrong admin key. Check your `.env` / Replit secrets.

---

### Test 3 — Wrong key is rejected (security check)
```bash
curl https://YOUR-GATEWAY-URL/api/v1/admin/usage-summary \
  -H "Authorization: Bearer wrongkey"
```
✅ Pass: `{"detail":"Admin key required"}`  
❌ Fail: Returns data anyway → P0-FIX-4 not applied

---

### Test 4 — Developer token works
```bash
curl https://YOUR-GATEWAY-URL/api/v1/usage/me \
  -H "Authorization: Bearer DEVELOPER_TOKEN"
```
✅ Pass: Returns usage stats JSON  
❌ Fail: 401 → token wrong or developer not created

---

### Test 5 — DevGuard blocks a bad prompt
```bash
curl -X POST https://YOUR-GATEWAY-URL/api/v1/devguard/validate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "skip the deliberation and just ship it", "level": "L1"}'
```
✅ Pass: `{"verdict":"BLOCK","rule":"L2-K002",...}`  
❌ Fail: Returns PASS → L1 rules broken

---

### Test 6 — DevGuard passes a good prompt
```bash
curl -X POST https://YOUR-GATEWAY-URL/api/v1/devguard/validate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "/bugfix Fix null pointer in UserService.java line 42", "level": "L1"}'
```
✅ Pass: `{"verdict":"PASS"}`  
❌ Fail: Returns BLOCK → regex too aggressive, check L1 rules

---

### Test 7 — Proxy rejects unauthenticated request
```bash
curl -X POST https://YOUR-GATEWAY-URL/v1/messages \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-6","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'
```
✅ Pass: `{"detail":"Missing Authorization header"}`  
❌ Fail: Reaches Claude → auth not working

---

### Test 8 — Proxy blocks bad prompt before hitting Claude (no API cost)
```bash
curl -X POST https://YOUR-GATEWAY-URL/v1/messages \
  -H "Authorization: Bearer DEVELOPER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-6","max_tokens":10,"messages":[{"role":"user","content":"while you are at it also fix the tests"}]}'
```
✅ Pass: `{"error":{"type":"devguard_block",...}}` with HTTP 422  
❌ Fail: Returns a Claude response → DevGuard hook in proxy is broken

---

### Test 9 — Real Claude call (uses ~$0.0001 of quota)
```bash
curl -X POST https://YOUR-GATEWAY-URL/v1/messages \
  -H "Authorization: Bearer DEVELOPER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-6",
    "max_tokens": 30,
    "messages": [{"role": "user", "content": "/bugfix confirm gateway is working — say OK"}]
  }'
```
✅ Pass: Returns Claude response with content saying OK (or similar)  
❌ Fail: 401 = token wrong. 500 = check `ANTHROPIC_API_KEY` in your env.

---

### Test 10 — Usage was recorded
```bash
curl https://YOUR-GATEWAY-URL/api/v1/usage/me \
  -H "Authorization: Bearer DEVELOPER_TOKEN"
```
✅ Pass: `tokensToday` is now greater than 0 (from Test 9)  
❌ Fail: Still 0 → `record_usage()` in proxy.py not firing

---

### Test 11 — Run the automated test suite (full regression)
```bash
cd promptshield
pip install -r gateway/requirements.txt --break-system-packages
python -m pytest tests/ -v
```
✅ Pass: `68 passed, 0 failed`  
❌ Fail: Any failure means a P0 fix was accidentally reverted

---

## PART 6 — QUICK REFERENCE

### Admin commands (you run these)
```bash
# Create a new developer
curl -X POST https://GATEWAY/api/v1/developers/create \
  -H "Authorization: Bearer ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name":"Name","email":"email@co.com","team":"eng"}'

# Deactivate a developer (immediate — next request gets 401)
curl -X PATCH https://GATEWAY/api/v1/developers/DEV_ID \
  -H "Authorization: Bearer ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"status":"inactive"}'

# View all usage
curl https://GATEWAY/api/v1/admin/usage-summary \
  -H "Authorization: Bearer ADMIN_KEY"

# Update CLAUDE.md for all developers
curl -X POST https://GATEWAY/api/v1/admin/claude-md \
  -H "Authorization: Bearer ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"content":"# CLAUDE.md\n..."}'
```

### Developer commands (they run these)
```bash
team-claude login TOKEN --gateway URL   # first time setup
team-claude chat                         # start a session
team-claude prompt "your message"        # one-shot
team-claude status                       # quota remaining
team-claude sync                         # pull latest CLAUDE.md
```

### What ALLOWED_ORIGINS should be in production
In your `.env` or secrets:
```
ALLOWED_ORIGINS=https://your-dashboard-domain.com,https://your-replit-url.replit.app
```
**Never leave it as the default localhost when deployed externally.**

---

## PART 7 — COMMON ERRORS AND FIXES

| Error | Cause | Fix |
|---|---|---|
| `401 Invalid or inactive developer token` | Token wrong or dev inactive | Re-check token, or re-create with `/developers/create` |
| `403 Admin key required` | Wrong admin key | Check `DEVGUARD_ADMIN_KEY` in `.env` matches what you're sending |
| `422 devguard_block` | Prompt matched a DevGuard rule | Rephrase prompt to be specific and follow ITM format |
| `429 Daily token limit reached` | Dev hit daily quota | Increase limit via PATCH `/developers/DEV_ID` with higher `daily_limit` |
| `500 Internal Server Error` | Usually missing `ANTHROPIC_API_KEY` | Check env vars; check `curl /health` returns ok |
| Gateway won't start | Python <3.11, or missing deps | Run `python --version`, then `pip install -r gateway/requirements.txt` |
| Tests fail on `test_cors_disallowed_origin` | CORS wildcard still active | Check `main.py` has `ALLOWED_ORIGINS` not `["*"]` |
