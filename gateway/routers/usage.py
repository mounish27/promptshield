"""Usage reporting — receives events from developer hooks."""
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel
from datetime import datetime
from gateway.models.database import AsyncSessionLocal, Developer, UsageEvent
from sqlalchemy import select

router = APIRouter()

class UsageEventIn(BaseModel):
    ts: str | None = None
    developer: str | None = None
    token: str | None = None
    tool: str = "chat"
    inputTokens: int = 0
    outputTokens: int = 0
    totalTokens: int = 0
    costUsd: float = 0.0
    model: str = "claude-sonnet-4-6"
    devguardVerdict: str = "PASS"
    register: bool = False
    os: str = ""
    version: str = ""

@router.post("/usage")
async def report_usage(event: UsageEventIn, authorization: str = Header(default="")):
    token = authorization.removeprefix("Bearer ").strip()
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.token == token))
        dev = result.scalar_one_or_none()
        if not dev:
            raise HTTPException(401, "Invalid token")

        if event.register and dev.status == "pending":
            dev.status = "active"
        dev.last_seen_at = datetime.utcnow()
        if event.developer:
            dev.name = event.developer

        row = UsageEvent(
            developer_id=dev.id, developer_name=dev.name,
            tool=event.tool, model=event.model,
            input_tokens=event.inputTokens, output_tokens=event.outputTokens,
            total_tokens=event.totalTokens, cost_usd=event.costUsd,
            devguard_verdict=event.devguardVerdict,
        )
        db.add(row)
        await db.commit()
    return {"ok": True}

@router.post("/usage/pr-review")
async def report_pr_review(data: dict, authorization: str = Header(default="")):
    from gateway.routers.admin import verify_admin
    verify_admin(authorization)
    async with AsyncSessionLocal() as db:
        row = UsageEvent(
            developer_id="github-actions", developer_name="GitHub Actions",
            tool="pr-review", request_type="pr-review",
            devguard_verdict=data.get("verdict", "UNKNOWN"),
        )
        db.add(row)
        await db.commit()
    return {"ok": True}

@router.get("/usage/me")
async def my_usage(authorization: str = Header(default="")):
    token = authorization.removeprefix("Bearer ").strip()
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.token == token))
        dev = result.scalar_one_or_none()
        if not dev:
            raise HTTPException(401, "Invalid token")
        today = __import__('datetime').date.today()
        month_start = today.replace(day=1)
        from sqlalchemy import func
        dq = await db.execute(select(func.sum(UsageEvent.total_tokens)).where(UsageEvent.developer_id==dev.id).where(func.date(UsageEvent.ts)==today))
        mq = await db.execute(select(func.sum(UsageEvent.total_tokens),func.sum(UsageEvent.cost_usd)).where(UsageEvent.developer_id==dev.id).where(UsageEvent.ts>=month_start))
        pq = await db.execute(select(UsageEvent.devguard_verdict,func.count(UsageEvent.id)).where(UsageEvent.developer_id==dev.id).group_by(UsageEvent.devguard_verdict))
        vc={r[0]:r[1] for r in pq.all()}
        mt,mc=mq.one()
        return {"tokensToday":dq.scalar() or 0,"tokensMonth":mt or 0,"costMonth":round(mc or 0,4),"dailyLimit":dev.daily_limit,"monthlyLimit":dev.monthly_limit,"passed":vc.get("PASS",0),"warned":vc.get("WARN",0),"blocked":vc.get("BLOCK",0)}

@router.get("/usage/my-events")
async def my_events(authorization: str = Header(default="")):
    token = authorization.removeprefix("Bearer ").strip()
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.token == token))
        dev = result.scalar_one_or_none()
        if not dev:
            raise HTTPException(401, "Invalid token")
        from sqlalchemy import desc
        eq = await db.execute(
            select(UsageEvent)
            .where(UsageEvent.developer_id == dev.id)
            .order_by(desc(UsageEvent.ts))
            .limit(100)
        )
        events = [
            {
                "device": dev.name,
                "prompt": e.prompt_snippet if hasattr(e,"prompt_snippet") else e.tool,
                "verdict": e.devguard_verdict,
                "tokens": e.total_tokens,
                "cost": round(e.cost_usd, 4),
                "ts": e.ts.isoformat() if e.ts else None,
            }
            for e in eq.scalars().all()
        ]
    return {"events": events}
