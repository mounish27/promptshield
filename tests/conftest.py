"""
Shared pytest fixtures for PromptShield test suite.
Uses an in-memory SQLite DB so tests never touch the real DB.
"""
import os, uuid, pytest, pytest_asyncio
os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:///:memory:")
os.environ.setdefault("DEVGUARD_ADMIN_KEY", "test-admin-key-abc123")
os.environ.setdefault("ANTHROPIC_API_KEY", "sk-test-fake")
os.environ.setdefault("ALLOWED_ORIGINS", "http://localhost:3000")

from httpx import AsyncClient, ASGITransport
from gateway.main import app
from gateway.models.database import engine, Base, AsyncSessionLocal, Developer


@pytest_asyncio.fixture(autouse=True)
async def reset_db():
    """Recreate tables before every test — clean slate."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


@pytest_asyncio.fixture
async def client():
    """Async test client wired to the FastAPI app."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


@pytest_asyncio.fixture
async def dev_token():
    """Insert a test developer and return their token."""
    token = f"dev-{uuid.uuid4().hex[:12]}"
    async with AsyncSessionLocal() as db:
        db.add(Developer(
            id=str(uuid.uuid4()),
            name="Test Dev",
            email="dev@example.com",
            team="engineering",
            token=token,
            status="active",
            daily_limit=500_000,
            monthly_limit=5_000_000,
        ))
        await db.commit()
    return token


@pytest_asyncio.fixture
async def inactive_dev_token():
    """Developer with status=inactive."""
    token = f"inactive-{uuid.uuid4().hex[:12]}"
    async with AsyncSessionLocal() as db:
        db.add(Developer(
            id=str(uuid.uuid4()),
            name="Inactive Dev",
            email="inactive@example.com",
            team="engineering",
            token=token,
            status="inactive",
            daily_limit=500_000,
            monthly_limit=5_000_000,
        ))
        await db.commit()
    return token
