"""Admin endpoints — usage summary for GitHub Pages aggregator."""
import os, secrets
from fastapi import APIRouter, Header, HTTPException
from sqlalchemy import select, func, desc
from datetime import date, datetime, timedelta
from gateway.models.database import AsyncSessionLocal, Developer, UsageEvent, DevGuardBlock

router = APIRouter()
ADMIN_KEY = os.getenv("DEVGUARD_ADMIN_KEY", "")

def verify_admin(authorization: str):
    token = authorization.removeprefix("Bearer ").strip()
    # P0-FIX-4: secrets.compare_digest prevents timing attacks
    if not token or not ADMIN_KEY or not secrets.compare_digest(token, ADMIN_KEY):
        raise HTTPException(403, "Admin key required")

@router.get("/admin/usage-summary")
async def usage_summary(authorization: str = Header(default="")):
    verify_admin(authorization)
    today = date.today()
    month_start = today.replace(day=1)

    async with AsyncSessionLocal() as db:
        # developers with monthly stats
        devs_q = await db.execute(select(Developer))
        devs = devs_q.scalars().all()

        dev_data = []
        for d in devs:
            # monthly
            mq = await db.execute(
                select(func.sum(UsageEvent.total_tokens), func.sum(UsageEvent.cost_usd),
                       func.count(UsageEvent.id))
                .where(UsageEvent.developer_id == d.id)
                .where(UsageEvent.ts >= month_start)
            )
            m_tokens, m_cost, m_reqs = mq.one()

            # today
            dq = await db.execute(
                select(func.sum(UsageEvent.total_tokens))
                .where(UsageEvent.developer_id == d.id)
                .where(func.date(UsageEvent.ts) == today)
            )
            d_tokens = dq.scalar() or 0

            # pass/warn/block counts
            pq = await db.execute(
                select(UsageEvent.devguard_verdict, func.count(UsageEvent.id))
                .where(UsageEvent.developer_id == d.id)
                .group_by(UsageEvent.devguard_verdict)
            )
            verdict_counts = {r[0]: r[1] for r in pq.all()}

            dev_data.append({
                "id": d.id, "name": d.name, "team": d.team, "role": d.role,
                "status": d.status,
                "tokensToday": d_tokens,
                "tokensMonth": m_tokens or 0,
                "costMonth": round(m_cost or 0.0, 4),
                "requestsMonth": m_reqs or 0,
                "dailyLimit": d.daily_limit,
                "monthlyLimit": d.monthly_limit,
                "lastSeenAt": d.last_seen_at.isoformat() if d.last_seen_at else None,
                "passed": verdict_counts.get("PASS", 0),
                "warned": verdict_counts.get("WARN", 0),
                "blocked": verdict_counts.get("BLOCK", 0),
                "totalPrompts": sum(verdict_counts.values()),
                "active": d.last_seen_at and (datetime.utcnow() - d.last_seen_at).days < 7,
            })

        # global summary
        total_cost_q = await db.execute(
            select(func.sum(UsageEvent.cost_usd)).where(UsageEvent.ts >= month_start)
        )
        spent_mtd = total_cost_q.scalar() or 0.0

        today_q = await db.execute(
            select(func.sum(UsageEvent.total_tokens), func.count(UsageEvent.id))
            .where(func.date(UsageEvent.ts) == today)
        )
        t_tokens, t_reqs = today_q.one()

        blocks_q = await db.execute(
            select(func.count(UsageEvent.id))
            .where(func.date(UsageEvent.ts) == today)
            .where(UsageEvent.devguard_verdict == "BLOCK")
        )
        warns_q = await db.execute(
            select(func.count(UsageEvent.id))
            .where(func.date(UsageEvent.ts) == today)
            .where(UsageEvent.devguard_verdict == "WARN")
        )

        # 7-day cost trend
        daily_costs = []
        for i in range(6, -1, -1):
            day = today - timedelta(days=i)
            dq = await db.execute(
                select(func.sum(UsageEvent.cost_usd), func.sum(UsageEvent.total_tokens))
                .where(func.date(UsageEvent.ts) == day)
            )
            cost, tokens = dq.one()
            daily_costs.append({
                "day": day.strftime("%a"),
                "date": day.isoformat(),
                "cost": round(cost or 0.0, 3),
                "tokens": tokens or 0,
            })

        # recent events
        recent_q = await db.execute(
            select(UsageEvent).order_by(desc(UsageEvent.ts)).limit(50)
        )
        recent = [
            {"ts": e.ts.isoformat(), "developer": e.developer_name,
             "tool": e.tool, "totalTokens": e.total_tokens,
             "costUsd": round(e.cost_usd, 4), "devguardVerdict": e.devguard_verdict}
            for e in recent_q.scalars().all()
        ]

        return {
            "generatedAt": datetime.utcnow().isoformat(),
            "summary": {
                "spentMtd": round(spent_mtd, 4),
                "tokensToday": t_tokens or 0,
                "requestsToday": t_reqs or 0,
                "blocksToday": blocks_q.scalar() or 0,
                "warnsToday": warns_q.scalar() or 0,
            },
            "developers": dev_data,
            "dailyCosts": daily_costs,
            "recentEvents": recent,
        }

# ── CLAUDE.md serve + update endpoints ───────────────────────────────────────

@router.get("/claude-md")
async def get_claude_md(authorization: str = Header(default="")):
    """Serve CLAUDE.md to any authenticated developer for sync."""
    token = authorization.removeprefix("Bearer ").strip()
    async with AsyncSessionLocal() as db:
        from gateway.models.database import Developer
        result = await db.execute(select(Developer).where(Developer.token == token))
        dev = result.scalar_one_or_none()
    if not dev:
        raise HTTPException(403, "Invalid token")
    import pathlib
    for p in [".promptshield/CLAUDE.md", "CLAUDE.md", "../../CLAUDE.md", os.path.join(os.path.dirname(__file__), "../../CLAUDE.md")]:
        try:
            content = pathlib.Path(p).read_text()
            return {"ok": True, "content": content, "length": len(content)}
        except: pass
    return {"ok": False, "content": None, "length": 0}

@router.post("/admin/claude-md")
async def update_claude_md(data: dict, authorization: str = Header(default="")):
    """Admin: update CLAUDE.md content from the dashboard."""
    verify_admin(authorization)
    content = data.get("content", "")
    if not content:
        raise HTTPException(400, "Content required")
    import pathlib
    p = pathlib.Path(".promptshield/CLAUDE.md"); p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    # invalidate cache in proxy
    try:
        from gateway.routers.proxy import invalidate_claude_md_cache
        invalidate_claude_md_cache()
    except: pass
    return {"ok": True, "length": len(content)}

@router.post("/devguard/generate-claude-md")
async def generate_claude_md_endpoint(data: dict, authorization: str = Header(default="")):
    """Generate CLAUDE.md from project clues — called during install."""
    token = authorization.removeprefix("Bearer ").strip()
    async with AsyncSessionLocal() as db:
        from gateway.models.database import Developer
        result = await db.execute(select(Developer).where(Developer.token == token))
        dev = result.scalar_one_or_none()
    if not dev:
        raise HTTPException(403, "Invalid token")

    clues = data.get("clues", {})
    import anthropic, json as _json

    system = """You are PromptShield DevGuard. Generate a CLAUDE.md file for a developer's project.
Be concise — this is injected on every Claude Code session start. Include: Project name/stack,
sprint goal placeholder, two human gates, universal anti-patterns, and role briefs.
Return ONLY raw markdown — no explanation, no code fences."""

    user_msg = f"Generate CLAUDE.md for:\n{_json.dumps(clues, indent=2)}\n\nKeep under 60 lines."

    try:
        client = anthropic.AsyncAnthropic(api_key=os.getenv("ANTHROPIC_API_KEY",""))  # P0-FIX-2
        resp = await client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=800,
            system=system,
            messages=[{"role":"user","content":user_msg}],
        )
        content = resp.content[0].text
        return {"ok": True, "content": content}
    except Exception as e:
        raise HTTPException(500, f"Generation failed: {e}")
