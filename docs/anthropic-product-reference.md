# Anthropic Product Reference
> **PromptShield internal doc** — sourced from official Anthropic documentation (docs.claude.com / docs.anthropic.com).  
> Last verified: May 19, 2026. Always cross-check pricing at https://docs.anthropic.com/en/docs/about-claude/pricing before budgeting.

---

## Table of Contents

1. [Products Overview](#1-products-overview)
2. [Claude API — Models](#2-claude-api--models)
3. [Claude API — Pricing](#3-claude-api--pricing)
4. [Claude API — Cost Levers](#4-claude-api--cost-levers)
5. [Claude API — Rate Limits](#5-claude-api--rate-limits)
6. [Claude API — SDKs & Integration](#6-claude-api--sdks--integration)
7. [Claude Code — Installation & Setup](#7-claude-code--installation--setup)
8. [Claude Code — Agent SDK](#8-claude-code--agent-sdk)
9. [Claude.ai — Subscription Plans](#9-claudeai--subscription-plans)
10. [PromptShield-Specific Guidance](#10-promptshield-specific-guidance)
11. [Official Sources](#11-official-sources)

---

## 1. Products Overview

Anthropic offers three distinct product surfaces. They share Claude models but have different pricing, authentication, and use cases.

| Product | What it is | Auth | Billed by |
|---|---|---|---|
| **Claude API** | Programmatic access via REST (`/v1/messages`) | API key | Per token (MTok) |
| **Claude Code** | Agentic CLI for developers; also available as Agent SDK | OAuth or API key | Tokens consumed via API or subscription credits |
| **Claude.ai** | Consumer/team web + mobile chat interface | Email / SSO | Monthly subscription |

**PromptShield uses the Claude API exclusively.** The gateway intercepts developer requests and forwards them to `https://api.anthropic.com/v1/messages` with the organization's API key.

---

## 2. Claude API — Models

### Current generation (as of May 2026)

| Model | API ID | Context window | Max output | Best for |
|---|---|---|---|---|
| **Claude Opus 4.7** | `claude-opus-4-7` | 1M tokens | 128k tokens | Complex reasoning, agentic work, long-horizon engineering |
| **Claude Opus 4.6** | `claude-opus-4-6` | 1M tokens | 128k tokens | Flagship quality; 1M context at standard pricing |
| **Claude Sonnet 4.6** | `claude-sonnet-4-6` | 1M tokens | 64k tokens | Default for most production workloads — best price/quality |
| **Claude Haiku 4.5** | `claude-haiku-4-5-20251001` | 200K tokens | 64k tokens | High-volume, latency-sensitive tasks |

> **PromptShield default model:** `claude-sonnet-4-6` (set in `gateway/routers/proxy.py`).  
> **DevGuard L2 validation model:** `claude-haiku-4-5-20251001` (cheapest, fast, sufficient for validation).

### Key model facts

- **1M context window:** Opus 4.7, Opus 4.6, and Sonnet 4.6 all include 1M context at standard per-token pricing — no beta header, no surcharge. Requests are billed at the same per-token rate regardless of context size.
- **Haiku 4.5 context:** 200K tokens only. The old `context-1m-2025-08-07` beta header is **retired as of April 30, 2026** — do not use it.
- **Batch API max output:** Opus 4.7, Opus 4.6, and Sonnet 4.6 support up to 300k output tokens on the Message Batches API using the `output-300k-2026-03-24` beta header.
- **Extended thinking:** Supported on Opus 4.7, Opus 4.6, Sonnet 4.6. Haiku 4.5 does not support extended thinking.
- **Opus 4.7 tokenizer note:** Ships with a new tokenizer that can generate up to 35% more tokens for the same input text vs Opus 4.6. Per-token prices are unchanged, but effective cost per request may increase. Benchmark before migrating from Opus 4.6.
- **Fast mode (Opus 4.6):** Available at 6× standard pricing ($30/$150 per MTok) for latency-sensitive workloads. Requires the `fast-mode-2026-02-01` beta header.

### Deprecated / legacy models

| Model | Status | Migration path |
|---|---|---|
| Claude Haiku 3 (`claude-3-haiku-20240307`) | Retired April 20, 2026 | Migrate to Haiku 4.5 |
| Claude Sonnet 3.7 | Deprecated | Migrate to Sonnet 4.6 |
| Claude Opus 4.1 | Legacy (still available) | Migrate to Opus 4.6 or 4.7 |
| Claude Sonnet 4 / Opus 4 | Deprecated | Migrate to 4.6 generation |

---

## 3. Claude API — Pricing

> All prices in USD per million tokens (MTok). Verified against official Anthropic pricing pages, May 2026.

### Base rates (standard API, no discounts)

| Model | Input ($/MTok) | Output ($/MTok) | Context |
|---|---|---|---|
| Claude Opus 4.7 | $5.00 | $25.00 | 1M |
| Claude Opus 4.6 | $5.00 | $25.00 | 1M |
| Claude Sonnet 4.6 | $3.00 | $15.00 | 1M |
| Claude Haiku 4.5 | $1.00 | $5.00 | 200K |
| *(legacy) Claude Opus 4.1* | $15.00 | $75.00 | 200K |

**Output tokens cost 5× input across all current models.** Output-heavy workloads (like agentic coding with long responses) dominate spend faster than input-heavy pipelines.

### PromptShield cost model

PromptShield tracks cost in `gateway/routers/proxy.py` using:

```python
COST_PER_TOKEN = {
    "input":  0.000003,   # $3.00/MTok — Sonnet 4.6 rate
    "output": 0.000015,   # $15.00/MTok — Sonnet 4.6 rate
}
cost = input_tokens * 0.000003 + output_tokens * 0.000015
```

**Update these constants if you change the default model.** Haiku rates are $0.000001 input / $0.000005 output. Opus rates are $0.000005 / $0.000025.

### Practical monthly cost examples

At standard Sonnet 4.6 rates, a team of 5 developers doing moderate coding work:

| Scenario | Tokens/day | Monthly cost |
|---|---|---|
| Light use (5 devs × 50k tokens) | 250k | ~$7.50 |
| Moderate use (5 devs × 200k tokens) | 1M | ~$30 |
| Heavy use (5 devs × 500k tokens) | 2.5M | ~$75 |

With prompt caching (90% hit rate) and batch processing (50% off), effective costs drop 90–95%.

---

## 4. Claude API — Cost Levers

### Prompt caching (up to 90% savings on repeated input)

Cache frequently reused content — system prompts, tool definitions, long context, CLAUDE.md content — so subsequent calls read from cache instead of reprocessing.

| Cache operation | Cost |
|---|---|
| Cache write (5-min TTL) | 1.25× base input rate |
| Cache write (1-hour TTL) | 2× base input rate |
| Cache read (hit) | 0.1× base input rate (**90% discount**) |

**Important for PromptShield:** Cached input tokens do **not** count toward your ITPM rate limits on most models (exception: Haiku 3.5). This means high cache hit rates effectively multiply your throughput.

**PromptShield opportunity:** The CLAUDE.md system prompt is injected on every request via `inject_claude_md()` in `proxy.py`. This is a prime candidate for prompt caching — it's the same content on every request. Implementing cache headers on the CLAUDE.md prefix would reduce costs significantly at scale.

### Batch API (50% off everything)

The Message Batches API processes requests asynchronously with results returned within 24 hours.

- **50% discount** on both input and output tokens across all models
- Opus 4.7, Opus 4.6, and Sonnet 4.6 support up to **300k output tokens** with the `output-300k-2026-03-24` beta header
- Can be combined with prompt caching for up to **95% total savings**

**PromptShield relevance:** Not applicable to interactive chat (latency-sensitive), but useful for batch code reviews, usage report generation, or any non-interactive DevGuard L2 analysis.

### Model routing (5–25× cost spread)

| Use case | Recommended model | Rationale |
|---|---|---|
| DevGuard L2 validation | Haiku 4.5 | Cheap, fast, sufficient for policy checks |
| Developer chat / coding | Sonnet 4.6 | Best price/quality for most coding tasks |
| Complex refactoring / architecture | Opus 4.6 or 4.7 | Reserved for tasks that justify the premium |

PromptShield already follows this pattern: Haiku for L2 validation, Sonnet as the default proxy model.

### US-only inference (1.1× multiplier)

For compliance-sensitive workloads requiring data residency in the US, setting `inference_geo: "us"` applies a **1.1× pricing multiplier**. The default (`"global"`) uses standard pricing. PromptShield does not currently use this.

---

## 5. Claude API — Rate Limits

Rate limits are enforced separately per model class. Exceeding any limit returns HTTP `429` with a `Retry-After` header.

### Limit dimensions

- **RPM** — Requests per minute
- **ITPM** — Input tokens per minute (uncached only for most models)
- **OTPM** — Output tokens per minute

### Key facts for PromptShield

1. **Cached tokens don't count toward ITPM** on most models. With 80% cache hit rate and 2M ITPM limit, effective throughput is 10M total input tokens/minute.
2. **Rate limits apply per workspace**, not per developer. PromptShield's per-developer quota enforcement (in `proxy.py:check_quota()`) is separate from and additive to Anthropic's own rate limits.
3. **Acceleration limits:** Sharp spikes in usage can trigger 429s even within rate limits. Ramp traffic gradually; avoid sudden bursts.
4. **Check current limits:** In the Claude Console → Settings → Rate Limits. Or query the Rate Limits API programmatically.

### Handling 429s in PromptShield

Currently `proxy.py` does not implement retry logic on 429/529 responses — this is listed as a P1 improvement. Add exponential backoff with the `Retry-After` header value before going to production.

```python
# TODO (P1): Add retry logic
# On 429: read resp.headers["Retry-After"], sleep, retry with backoff
# On 529: retry up to 3× with exponential backoff
```

---

## 6. Claude API — SDKs & Integration

### Python SDK (used in PromptShield gateway)

```bash
pip install anthropic
```

```python
# Sync client (DO NOT use in async context — P0 fix applied)
from anthropic import Anthropic
client = Anthropic(api_key="sk-ant-...")

# Async client (correct for FastAPI — P0 fix)
from anthropic import AsyncAnthropic
client = AsyncAnthropic(api_key="sk-ant-...")
resp = await client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1000,
    messages=[{"role": "user", "content": "Hello"}]
)
```

**PromptShield P0 fix applied:** All three files that called the Anthropic API (`devguard_validate.py`, `proxy.py`, `admin.py`) were updated to use `AsyncAnthropic` with `await`. Using the sync client inside `async def` blocks the event loop.

### Available official SDKs

| Language | Install |
|---|---|
| Python | `pip install anthropic` |
| TypeScript / Node | `npm install @anthropic-ai/sdk` |
| Java | Maven / Gradle: `com.anthropic:anthropic-java` |
| Go | `go get github.com/anthropics/anthropic-sdk-go` |
| Ruby, C#, PHP | Available — see docs |

### Authentication

Set the API key as an environment variable (never hardcode):

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

The SDK reads `ANTHROPIC_API_KEY` automatically. PromptShield stores this in `.env` on the gateway server only — developers never see it.

### Messages API endpoint

```
POST https://api.anthropic.com/v1/messages
```

Required headers:
```
x-api-key: <your-api-key>
anthropic-version: 2023-06-01
content-type: application/json
```

PromptShield sets these in `proxy.py:proxy_messages()` before forwarding.

---

## 7. Claude Code — Installation & Setup

Claude Code is an agentic CLI for developers. PromptShield's DevGuard hooks integrate with Claude Code on developer machines.

### System requirements

- **macOS** 10.15+
- **Linux** Ubuntu 20.04+ / Debian 10+
- **Windows** 10+ with WSL 1, WSL 2, or Git for Windows

### Installation (npm — traditional method)

```bash
npm install -g @anthropic-ai/claude-code
```

> Do **NOT** use `sudo npm install -g` — this causes permission and security issues.

### Installation (native binary — preferred)

```bash
# Stable version
curl -fsSL https://claude.ai/install.sh | bash

# Latest version
curl -fsSL https://claude.ai/install.sh | bash -s latest

# Specific version
curl -fsSL https://claude.ai/install.sh | bash -s 1.0.58
```

Run `claude doctor` after installation to verify your installation type and version.

### Authentication options

1. **Claude Console (default):** Run `claude`, complete OAuth in browser
2. **API key:** Set `ANTHROPIC_API_KEY` env var for headless/CI use
3. **AWS Bedrock:** Set `CLAUDE_CODE_USE_BEDROCK=1` + AWS credentials
4. **Google Vertex AI:** Set `CLAUDE_CODE_USE_VERTEX=1` + GCP credentials
5. **Microsoft Azure:** Set `CLAUDE_CODE_USE_FOUNDRY=1` + Azure credentials
6. **Claude Platform on AWS:** Set `CLAUDE_CODE_USE_ANTHROPIC_AWS=1` + `ANTHROPIC_AWS_WORKSPACE_ID`

### CLAUDE.md — project context file

Claude Code reads `CLAUDE.md` at the start of every session. PromptShield uses this to inject project context, DevGuard rules, sprint goals, and anti-patterns into every developer session.

- Located at project root or `.promptshield/CLAUDE.md`
- Generated by `devguard/generate-claude-md.js` during install
- Synced from the gateway by `devguard/claude-md-sync.js`
- Admin can update it via the dashboard → `/api/v1/admin/claude-md`
- Gateway injects CLAUDE.md into every API request via `proxy.py:inject_claude_md()`

### Claude Code hooks (used by PromptShield DevGuard)

Hooks fire at key points in the Claude Code agent lifecycle:

| Hook | When it fires | PromptShield use |
|---|---|---|
| `PreToolUse` | Before every tool call | `devguard/pre-tool-hook.js` — validates & blocks bad prompts |
| `PostToolUse` | After every tool call | `devguard/usage-reporter.js` — sends token telemetry to gateway |
| `SessionStart` | Session begins | `devguard/session-start.js` — syncs CLAUDE.md, registers device |
| `UserPromptSubmit` | User submits a prompt | Available for prompt validation |
| `Stop` | Session ends | Available for session cleanup |

Hooks are configured in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "node ~/.devguard/bin/pre-tool-hook.js"}]}],
    "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "node ~/.devguard/bin/usage-reporter.js"}]}]
  }
}
```

---

## 8. Claude Code — Agent SDK

> **Renamed:** The Claude Code SDK has been renamed to the **Claude Agent SDK**. Migration is a one-line package name change.

### What it is

The Agent SDK gives programmatic access to Claude's full agentic capabilities (file reading, command execution, web search, code editing) in Python and TypeScript. It's what powers Claude Code itself, exposed as a library.

### Migration from Claude Code SDK

```python
# Before
from claude_code_sdk import query, ClaudeCodeOptions
options = ClaudeCodeOptions(model="claude-opus-4-6")

# After
from claude_agent_sdk import query, ClaudeAgentOptions
options = ClaudeAgentOptions(model="claude-opus-4-6")
```

**Breaking changes in v0.1.0:**
- `ClaudeCodeOptions` renamed to `ClaudeAgentOptions`
- SDK no longer uses Claude Code's system prompt by default (opt-in with `setting_sources=["project"]`)
- SDK no longer reads filesystem settings by default

### PromptShield relevance

The Agent SDK is not currently used by PromptShield, but it's a path for building more sophisticated DevGuard workflows — e.g., an automated code review agent that reads files, runs tests, and produces the review report programmatically instead of via slash commands.

---

## 9. Claude.ai — Subscription Plans

This section covers Claude.ai consumer plans. These are **separate from the API** and not used by PromptShield directly.

| Plan | Price | Key limits |
|---|---|---|
| **Free** | $0 | Limited messages on Sonnet; no API access |
| **Pro** | ~$20/month | Higher limits; access to Opus; Projects |
| **Max** | Higher tier | Highest usage limits |
| **Team** | Per seat | Shared workspace, admin controls |
| **Enterprise** | Custom | SSO, SAML, custom data retention, SLAs |

**Agent SDK credits (June 15, 2026):** Starting June 15, 2026, Agent SDK and `claude -p` usage on subscription plans draws from a separate monthly Agent SDK credit, distinct from interactive usage limits.

**PromptShield does not use claude.ai subscriptions.** Developers use the `team-claude` CLI which routes through the PromptShield gateway to the Claude API. The $200/month budget referenced in the original spec is an API billing budget, not a claude.ai subscription.

---

## 10. PromptShield-Specific Guidance

### Model IDs to use in code

```python
# Production chat proxy (proxy.py default)
model = "claude-sonnet-4-6"

# DevGuard L2 validation (devguard_validate.py)
model = "claude-haiku-4-5-20251001"

# CLAUDE.md generation (admin.py)
model = "claude-haiku-4-5-20251001"
```

Do **not** use old model IDs like `claude-3-haiku-20240307` (retired) or `claude-3-5-sonnet` (deprecated).

### Cost tracking accuracy

The `COST_PER_TOKEN` dict in `proxy.py` is currently hardcoded to Sonnet 4.6 rates. If an admin or developer selects a different model in their request body, the logged cost will be wrong. A future improvement is to look up the model dynamically:

```python
MODEL_COSTS = {
    "claude-opus-4-7":           {"input": 0.000005, "output": 0.000025},
    "claude-opus-4-6":           {"input": 0.000005, "output": 0.000025},
    "claude-sonnet-4-6":         {"input": 0.000003, "output": 0.000015},
    "claude-haiku-4-5-20251001": {"input": 0.000001, "output": 0.000005},
}
def get_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    rates = MODEL_COSTS.get(model, MODEL_COSTS["claude-sonnet-4-6"])
    return input_tokens * rates["input"] + output_tokens * rates["output"]
```

### $200/month budget planning

At Sonnet 4.6 rates ($3/$15 per MTok), $200 buys approximately:

- Pure input: 66.7 million input tokens
- Mixed 3:1 input/output: ~30 million input + 10 million output tokens
- Typical coding session (2k input, 1k output per request): ~8,300 requests/month

With 5 developers at 500k tokens/day, monthly spend is ~$75 at standard rates. The $200 budget provides significant headroom. The 90% threshold alert in the original spec (~$180) is reasonable.

### Security reminders

All 4 P0 fixes have been applied and tested. Remaining security items before first external user:

1. Hash developer tokens in the DB (currently stored plaintext) — P1
2. Add input size limits to prevent token flooding — P1  
3. Implement retry logic for 429/529 from Anthropic API — P1
4. Lock down `ALLOWED_ORIGINS` to your actual deployment domain in `.env` (currently defaults to localhost) — **do this before deploying**

---

## 11. Official Sources

All information in this document was verified against these official Anthropic sources:

| Topic | URL |
|---|---|
| Models overview | https://docs.anthropic.com/en/docs/about-claude/models/overview |
| Pricing | https://docs.anthropic.com/en/docs/about-claude/pricing |
| Rate limits | https://docs.claude.com/en/api/rate-limits |
| Context windows | https://docs.anthropic.com/en/docs/build-with-claude/context-windows |
| Client SDKs | https://docs.anthropic.com/en/api/client-sdks |
| Claude Code setup | https://docs.claude.com/en/docs/claude-code/setup |
| Agent SDK overview | https://docs.claude.com/en/docs/claude-code/sdk/sdk-overview |
| Agent SDK migration | https://docs.claude.com/en/docs/claude-code/sdk/migration-guide |
| Platform release notes | https://docs.claude.com/en/release-notes/overview |
| Claude.ai help center | https://support.claude.com |
| Prompt caching | https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching |
| Extended thinking | https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking |
