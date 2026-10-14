"""Developer registration and token management."""
import uuid, secrets
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel
from gateway.models.database import AsyncSessionLocal, Developer
from sqlalchemy import select

router = APIRouter()

class RegisterIn(BaseModel):
    name: str
    installedAt: str | None = None
    os: str = ""
    version: str = ""
    email: str | None = None
    team: str = ""

@router.post("/developers/register")
async def register(data: RegisterIn, authorization: str = Header(default="")):
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(401, "Token required")

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.token == token))
        dev = result.scalar_one_or_none()
        if dev:
            dev.name = data.name
            if dev.status == "pending":
                dev.status = "active"
            from datetime import datetime
            dev.last_seen_at = datetime.utcnow()
            await db.commit()
            return {"ok": True, "developer": dev.name, "status": dev.status}
        raise HTTPException(401, "Token not found — generate one from the admin dashboard")

@router.post("/developers/create")
async def create_developer(data: RegisterIn, authorization: str = Header(default="")):
    """Admin only — create a new developer and return their token."""
    from gateway.routers.admin import verify_admin
    verify_admin(authorization)
    token = secrets.token_urlsafe(32)
    dev_id = str(uuid.uuid4())
    async with AsyncSessionLocal() as db:
        dev = Developer(id=dev_id, name=data.name, email=data.email,
                        team=data.team, token=token, role="developer")
        db.add(dev)
        await db.commit()
    return {"ok": True, "token": token, "id": dev_id}

class UpdateDeveloper(BaseModel):
    daily_limit: int | None = None
    monthly_limit: int | None = None
    role: str | None = None
    status: str | None = None

@router.patch("/developers/{dev_id}")
async def update_developer(dev_id: str, data: UpdateDeveloper, authorization: str = Header(default="")):
    from gateway.routers.admin import verify_admin
    verify_admin(authorization)
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.id == dev_id))
        dev = result.scalar_one_or_none()
        if not dev:
            raise HTTPException(404, "Developer not found")
        if data.daily_limit is not None: dev.daily_limit = data.daily_limit
        if data.monthly_limit is not None: dev.monthly_limit = data.monthly_limit
        if data.role is not None: dev.role = data.role
        if data.status is not None: dev.status = data.status
        await db.commit()
    return {"ok": True}

@router.post("/developers/regenerate-token")
async def regenerate_token(data: dict, authorization: str = Header(default="")):
    from gateway.routers.admin import verify_admin
    verify_admin(authorization)
    email = data.get("email", "")
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.email == email))
        dev = result.scalar_one_or_none()
        if not dev:
            raise HTTPException(404, f"No developer found with email {email}")
        dev.token = secrets.token_urlsafe(32)
        await db.commit()
        return {"ok": True, "token": dev.token}

import secrets as secrets_mod

class PregenRequest(BaseModel):
    count: int = 4
    label: str = ""  # e.g. "Shri's devices"

@router.post("/developers/pregen-device-ids")
async def pregen_device_ids(data: PregenRequest, authorization: str = Header(default="")):
    """Admin: pre-generate N device IDs. Developer picks one and inputs during install."""
    from gateway.routers.admin import verify_admin
    verify_admin(authorization)
    ids = []
    async with AsyncSessionLocal() as db:
        for i in range(min(data.count, 10)):
            dev_id = str(uuid.uuid4())
            # Generate short human-readable device token: DID-XXXX-XXXX-XXXX
            parts = [secrets_mod.token_hex(2).upper() for _ in range(3)]
            token = f"DID-{parts[0]}-{parts[1]}-{parts[2]}"
            dev = Developer(
                id=dev_id,
                name=f"Unregistered Device {i+1}" + (f" ({data.label})" if data.label else ""),
                token=token,
                role="developer",
                status="pending",   # pending until device registers
            )
            db.add(dev)
            ids.append({"id": dev_id, "token": token, "label": data.label})
        await db.commit()
    return {"ok": True, "device_ids": ids, "count": len(ids)}

@router.get("/developers/device-ids")
async def list_device_ids(authorization: str = Header(default="")):
    """Admin: list all pre-generated device IDs with their status."""
    from gateway.routers.admin import verify_admin
    verify_admin(authorization)
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Developer).where(Developer.status.in_(["pending", "active", "inactive"]))
        )
        devs = result.scalars().all()
    return {"devices": [
        {
            "id": d.id, "name": d.name, "token": d.token,
            "status": d.status, "role": d.role, "team": d.team or "",
            "lastSeenAt": d.last_seen_at.isoformat() if d.last_seen_at else None,
        }
        for d in devs
    ]}
