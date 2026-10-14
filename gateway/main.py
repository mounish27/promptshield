"""
PromptShield Gateway — FastAPI proxy between developers and Claude API.
Validates prompts via DevGuard, routes to Claude, tracks usage.
"""
from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from pathlib import Path
import uvicorn, os
from fastapi.responses import FileResponse, RedirectResponse
from gateway.routers import proxy, usage, admin, developers, devguard_validate, reviews

ROOT = Path(__file__).resolve().parents[1]
DASHBOARD_PATH = ROOT / "github-pages" / "index.html"

@asynccontextmanager
async def lifespan(app: FastAPI):
    from gateway.models.database import init_db
    await init_db()
    yield

app = FastAPI(
    title="PromptShield Gateway",
    description="AI developer governance platform — proxy, DevGuard, token tracking",
    version="1.0.0",
    lifespan=lifespan,
)

# P0-FIX-3: never wildcard — read from env, default to localhost only
_raw_origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173")
ALLOWED_ORIGINS = [o.strip() for o in _raw_origins.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)

@app.get("/")
async def root():
    return RedirectResponse(url="/dashboard")

@app.get("/dashboard")
async def dashboard():
    return FileResponse(str(DASHBOARD_PATH))

@app.get("/install.sh")
async def serve_install_sh():
    return FileResponse(str(ROOT / "install.sh"), media_type="text/plain")

app.include_router(proxy.router,              prefix="/v1",        tags=["proxy"])
app.include_router(devguard_validate.router,  prefix="/api/v1",    tags=["devguard"])
app.include_router(usage.router,              prefix="/api/v1",    tags=["usage"])
app.include_router(admin.router,              prefix="/api/v1",    tags=["admin"])
app.include_router(developers.router,         prefix="/api/v1",    tags=["developers"])
app.include_router(reviews.router,            prefix="/api/v1",    tags=["reviews"])

@app.get("/health")
async def health():
    return {"status": "ok", "service": "promptshield-gateway"}

if __name__ == "__main__":
    uvicorn.run("gateway.main:app", host="0.0.0.0", port=8000, reload=True)
