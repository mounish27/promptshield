"""
PromptShield Gateway Proxy — Gap 2 fix
Intercepts all /v1/messages requests, runs DevGuard validation,
INJECTS CLAUDE.MD as system prompt context, forwards to Claude, tracks tokens.
"""
import os, time, json, httpx
from fastapi import APIRouter, Request, HTTPException, Header
from fastapi.responses import JSONResponse
from sqlalchemy import select, func
from gateway.models.database import AsyncSessionLocal, Developer, UsageEvent, DevGuardBlock
from gateway.routers.devguard_validate import (
    validate_prompt_local,
    validate_prompt_remote,
    extract_prompt_from_messages,
)

router = APIRouter()

CLAUDE_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
CLAUDE_BASE    = "https://api.anthropic.com"
CLAUDE_MD_PATH = os.getenv("CLAUDE_MD_PATH", ".promptshield/CLAUDE.md")

COST_PER_TOKEN = {
    "input":  0.000003,
    "output": 0.000015,
}

# ── Gap 2: load CLAUDE.md once at startup ─────────────────────────────────────
_CLAUDE_MD_CACHE: str | None = None

def load_claude_md() -> str | None:
    """Load CLAUDE.md from disk. Returns content or None."""
    global _CLAUDE_MD_CACHE
    if _CLAUDE_MD_CACHE is not None:
        return _CLAUDE_MD_CACHE
    for path in [CLAUDE_MD_PATH, ".promptshield/CLAUDE.md", "CLAUDE.md", os.path.join(os.path.dirname(__file__), "../../CLAUDE.md")]:
        if os.path.exists(path):
            try:
                _CLAUDE_MD_CACHE = open(path).read().strip()
                return _CLAUDE_MD_CACHE
            except Exception:
                pass
    return None

def inject_claude_md(body: dict) -> dict:
    """
    Gap 2: Inject CLAUDE.md as the system prompt prefix on every request.
    If request already has a system prompt, prepend CLAUDE.md to it.
    If no system prompt, add one.
    """
    claude_md = load_claude_md()
    if not claude_md:
        return body

    system_injection = f"""# PromptShield — Project Context
{claude_md}

---
# Developer request follows
"""
    existing_system = body.get("system", "")
    if existing_system:
        body["system"] = system_injection + "\n" + existing_system
    else:
        body["system"] = system_injection

    return body

def invalidate_claude_md_cache():
    """Call this when CLAUDE.md is updated via the admin dashboard."""
    global _CLAUDE_MD_CACHE
    _CLAUDE_MD_CACHE = None

# ── Developer auth ────────────────────────────────────────────────────────────
async def get_developer(authorization: str) -> Developer | None:
    token = authorization.removeprefix("Bearer ").strip()
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.token == token))
        return result.scalar_one_or_none()

async def check_quota(dev: Developer) -> dict:
    from datetime import date
    today = date.today()
    async with AsyncSessionLocal() as db:
        daily = await db.execute(
            select(func.sum(UsageEvent.total_tokens))
            .where(UsageEvent.developer_id == dev.id)
            .where(func.date(UsageEvent.ts) == today)
        )
        if (daily.scalar() or 0) >= dev.daily_limit:
            return {"ok": False, "reason": f"Daily token limit reached ({dev.daily_limit:,}). Resets at midnight."}
        month_start = today.replace(day=1)
        monthly = await db.execute(
            select(func.sum(UsageEvent.total_tokens))
            .where(UsageEvent.developer_id == dev.id)
            .where(UsageEvent.ts >= month_start)
        )
        if (monthly.scalar() or 0) >= dev.monthly_limit:
            return {"ok": False, "reason": f"Monthly token limit reached ({dev.monthly_limit:,})."}
    return {"ok": True}

def detect_client_tool(request: Request) -> str:
    """Tag usage as cursor vs claude CLI based on User-Agent."""
    ua = request.headers.get("user-agent", "")
    if "cursor" in ua.lower():
        return "cursor"
    return "chat"


async def record_usage(dev, body, response, verdict, rule, duration_ms, tool: str = "chat"):
    usage = response.get("usage", {})
    inp   = usage.get("input_tokens", 0)
    out   = usage.get("output_tokens", 0)
    cost  = inp * COST_PER_TOKEN["input"] + out * COST_PER_TOKEN["output"]
    async with AsyncSessionLocal() as db:
        db.add(UsageEvent(
            developer_id=dev.id, developer_name=dev.name,
            tool=tool, model=body.get("model", "claude-sonnet-4-6"),
            input_tokens=inp, output_tokens=out, total_tokens=inp + out,
            cost_usd=cost, devguard_verdict=verdict, devguard_rule=rule,
            duration_ms=duration_ms,
        ))
        dev.last_seen_at = func.now()
        db.add(dev)
        await db.commit()

async def record_block(dev, rule, level, prompt, corrected):
    async with AsyncSessionLocal() as db:
        db.add(DevGuardBlock(
            developer_id=dev.id, developer_name=dev.name,
            rule=rule, level=level,
            prompt_snippet=prompt[:200],
            corrected=corrected,
        ))
        await db.commit()

# ── Gap 2: prompt rewrite endpoint (called by Mode B hook) ───────────────────
from pydantic import BaseModel

class RewriteRequest(BaseModel):
    prompt: str
    claudeMd: str | None = None

@router.post("/api/v1/devguard/rewrite")
async def rewrite_prompt(req: RewriteRequest, authorization: str = Header(default="")):
    """Gap 1+2: Takes a raw prompt, returns an improved version using CLAUDE.md context."""
    token = authorization.removeprefix("Bearer ").strip()
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.token == token))
        dev = result.scalar_one_or_none()
    if not dev:
        raise HTTPException(401, "Invalid token")

    claude_md = req.claudeMd or load_claude_md() or ""

    system = f"""You are PromptShield DevGuard. Rewrite this developer prompt into the best possible ITM slash command.

## Project context
{claude_md}

## Rules
- Produce a specific /command with complete, precise arguments
- Bug descriptions: symptom + file/function + how to reproduce
- Feature descriptions: ≥5 words + observable success criteria
- One command per prompt — never combine actions
- Remove scope creep, vague qualifiers, unbounded scope
- Reference file paths explicitly

Return ONLY raw JSON (no markdown):
{{"rewritten": "improved prompt", "changes": "one sentence", "token_saving": "estimate"}}"""

    try:
        import anthropic
        client = anthropic.AsyncAnthropic(api_key=CLAUDE_API_KEY)  # P0-FIX-2
        resp = await client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=400,
            system=system,
            messages=[{"role": "user", "content": f"Rewrite:\n\n{req.prompt}"}],
        )
        text = resp.content[0].text.replace("```json", "").replace("```", "").strip()
        return json.loads(text)
    except Exception as e:
        return {"rewritten": req.prompt, "changes": f"Could not rewrite: {e}", "token_saving": "0"}

# ── Main proxy endpoint ───────────────────────────────────────────────────────
@router.post("/messages")
async def proxy_messages(request: Request, authorization: str = Header(default="")):
    if not authorization:
        raise HTTPException(401, "Missing Authorization header")

    dev = await get_developer(authorization)
    if not dev or dev.status != "active":
        raise HTTPException(401, "Invalid or inactive developer token")

    body = await request.json()
    tool = detect_client_tool(request)
    prompt_text = extract_prompt_from_messages(body)

    # DevGuard L1
    local_result = validate_prompt_local(prompt_text)
    if local_result["verdict"] == "BLOCK":
        await record_block(dev, local_result["rule"], "L1", prompt_text, local_result.get("corrected"))
        return JSONResponse(status_code=422, content={
            "error": {
                "type": "devguard_block",
                "message": f"DevGuard L1 [{local_result['rule']}]: {local_result['msg']}",
                "corrected_prompt": local_result.get("corrected"),
                "rule": local_result["rule"],
                "level": "L1",
            }
        })

    # Quota check
    quota = await check_quota(dev)
    if not quota["ok"]:
        raise HTTPException(429, quota["reason"])

    # Gap 2: inject CLAUDE.md into every request
    body = inject_claude_md(body)

    # Forward to Claude
    headers = {
        "x-api-key": CLAUDE_API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    start = time.monotonic()
    async with httpx.AsyncClient(timeout=120) as client:
        resp = await client.post(f"{CLAUDE_BASE}/v1/messages", json=body, headers=headers)
    duration_ms = int((time.monotonic() - start) * 1000)
    response_data = resp.json()

    verdict = "WARN" if local_result["verdict"] == "WARN" else "PASS"
    await record_usage(
        dev, body, response_data, verdict,
        local_result.get("rule") if verdict == "WARN" else None,
        duration_ms,
        tool=tool,
    )

    return JSONResponse(status_code=resp.status_code, content=response_data)

# ── Admin: reload CLAUDE.md without restarting ────────────────────────────────
@router.post("/api/v1/admin/reload-claude-md")
async def reload_claude_md(authorization: str = Header(default="")):
    from gateway.routers.admin import verify_admin
    verify_admin(authorization)
    invalidate_claude_md_cache()
    new_content = load_claude_md()
    return {"ok": True, "loaded": new_content is not None, "length": len(new_content) if new_content else 0}
