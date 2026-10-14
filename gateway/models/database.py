"""Database setup — SQLite for local dev, PostgreSQL for production."""
import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy import Column, String, Integer, Float, DateTime, Boolean, Text, func

_raw_url = os.getenv("DATABASE_URL", "sqlite+aiosqlite:///./promptshield.db")

# Normalise URL scheme for asyncpg
if _raw_url.startswith("postgres://"):
    _raw_url = _raw_url.replace("postgres://", "postgresql+asyncpg://", 1)
elif _raw_url.startswith("postgresql://"):
    _raw_url = _raw_url.replace("postgresql://", "postgresql+asyncpg://", 1)

DATABASE_URL = _raw_url
_is_postgres = "asyncpg" in DATABASE_URL

# Supabase pgbouncer transaction pooler requires prepared_statement_cache_size=0
# This must be set in connect_args to prevent DuplicatePreparedStatementError
engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    connect_args={"prepared_statement_cache_size": 0} if _is_postgres else {},
    execution_options={"compiled_cache": None} if _is_postgres else {},
)

AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
Base = declarative_base()

class Developer(Base):
    __tablename__ = "developers"
    id            = Column(String, primary_key=True)
    name          = Column(String, nullable=False)
    email         = Column(String, unique=True)
    team          = Column(String, default="")
    role          = Column(String, default="developer")
    token         = Column(String, unique=True, nullable=False)
    status        = Column(String, default="active")
    daily_limit   = Column(Integer, default=500_000)
    monthly_limit = Column(Integer, default=5_000_000)
    created_at    = Column(DateTime, server_default=func.now())
    last_seen_at  = Column(DateTime)

class UsageEvent(Base):
    __tablename__ = "usage_events"
    id               = Column(Integer, primary_key=True, autoincrement=True)
    developer_id     = Column(String, nullable=False)
    developer_name   = Column(String)
    ts               = Column(DateTime, server_default=func.now())
    tool             = Column(String, default="chat")
    model            = Column(String, default="claude-sonnet-4-6")
    input_tokens     = Column(Integer, default=0)
    output_tokens    = Column(Integer, default=0)
    total_tokens     = Column(Integer, default=0)
    cost_usd         = Column(Float, default=0.0)
    devguard_verdict = Column(String, default="PASS")
    devguard_rule    = Column(String)
    request_type     = Column(String, default="chat")
    duration_ms      = Column(Integer, default=0)

class DevGuardBlock(Base):
    __tablename__ = "devguard_blocks"
    id             = Column(Integer, primary_key=True, autoincrement=True)
    developer_id   = Column(String, nullable=False)
    developer_name = Column(String)
    ts             = Column(DateTime, server_default=func.now())
    rule           = Column(String)
    level          = Column(String)
    prompt_snippet = Column(Text)
    corrected      = Column(Text)

class ReviewLog(Base):
    __tablename__ = "review_logs"
    id                  = Column(Integer, primary_key=True, autoincrement=True)
    developer_id        = Column(String, nullable=False)
    developer_name      = Column(String)
    ts                  = Column(DateTime, server_default=func.now())
    verdict             = Column(String, default="UNKNOWN")
    files_reviewed      = Column(Integer, default=0)
    blocking_issues     = Column(Integer, default=0)
    warnings            = Column(Integer, default=0)
    deliberation_status = Column(String, default="UNKNOWN")
    security_status     = Column(String, default="PASS")
    test_status         = Column(String, default="UNKNOWN")
    quality_status      = Column(String, default="PASS")
    summary             = Column(Text)
    report_content      = Column(Text)
    story_path          = Column(String)
    cwd                 = Column(String)

async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
