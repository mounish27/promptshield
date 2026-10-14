"""
Review log endpoints — receives review reports from developers,
stores them, serves them to the dashboard.
"""
import os
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel
from sqlalchemy import select, desc
from datetime import datetime
from gateway.models.database import AsyncSessionLocal, Developer, ReviewLog

router = APIRouter()

class ReviewIn(BaseModel):
    ts: str | None = None
    developer: str | None = None
    deviceName: str | None = None
    type: str = "review"
    verdict: str = "UNKNOWN"
    filesReviewed: int = 0
    blocking: int = 0
    warnings: int = 0
    deliberationStatus: str = "UNKNOWN"
    securityStatus: str = "PASS"
    testStatus: str = "UNKNOWN"
    qualityStatus: str = "PASS"
    summary: str = ""
    reportContent: str | None = None
    storyPath: str | None = None
    cwd: str | None = None

@router.post("/reviews")
async def log_review(review: ReviewIn, authorization: str = Header(default="")):
    token = authorization.removeprefix("Bearer ").strip()
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.token == token))
        dev = result.scalar_one_or_none()
        if not dev:
            raise HTTPException(401, "Invalid token")

        row = ReviewLog(
            developer_id=dev.id,
            developer_name=dev.name,
            verdict=review.verdict,
            files_reviewed=review.filesReviewed,
            blocking_issues=review.blocking,
            warnings=review.warnings,
            deliberation_status=review.deliberationStatus,
            security_status=review.securityStatus,
            test_status=review.testStatus,
            quality_status=review.qualityStatus,
            summary=review.summary,
            report_content=review.reportContent,
            story_path=review.storyPath,
            cwd=review.cwd,
        )
        db.add(row)
        await db.commit()
    return {"ok": True}

@router.get("/reviews/my")
async def my_reviews(authorization: str = Header(default=""), limit: int = 20):
    token = authorization.removeprefix("Bearer ").strip()
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.token == token))
        dev = result.scalar_one_or_none()
        if not dev:
            raise HTTPException(401, "Invalid token")

        rq = await db.execute(
            select(ReviewLog)
            .where(ReviewLog.developer_id == dev.id)
            .order_by(desc(ReviewLog.ts))
            .limit(limit)
        )
        reviews = [
            {
                "id": r.id,
                "ts": r.ts.isoformat() if r.ts else None,
                "verdict": r.verdict,
                "filesReviewed": r.files_reviewed,
                "blocking": r.blocking_issues,
                "warnings": r.warnings,
                "deliberationStatus": r.deliberation_status,
                "securityStatus": r.security_status,
                "testStatus": r.test_status,
                "qualityStatus": r.quality_status,
                "summary": r.summary,
                "storyPath": r.story_path,
            }
            for r in rq.scalars().all()
        ]
    return {"reviews": reviews}

@router.get("/reviews/all")
async def all_reviews(authorization: str = Header(default=""), limit: int = 50):
    """Admin: all reviews across all developers."""
    from gateway.routers.admin import verify_admin
    verify_admin(authorization)
    async with AsyncSessionLocal() as db:
        rq = await db.execute(
            select(ReviewLog).order_by(desc(ReviewLog.ts)).limit(limit)
        )
        reviews = [
            {
                "id": r.id,
                "ts": r.ts.isoformat() if r.ts else None,
                "developer": r.developer_name,
                "verdict": r.verdict,
                "filesReviewed": r.files_reviewed,
                "blocking": r.blocking_issues,
                "warnings": r.warnings,
                "deliberationStatus": r.deliberation_status,
                "securityStatus": r.security_status,
                "summary": r.summary,
                "storyPath": r.story_path,
            }
            for r in rq.scalars().all()
        ]
    return {"reviews": reviews}

@router.get("/reviews/{review_id}/report")
async def get_report(review_id: int, authorization: str = Header(default="")):
    """Get full markdown report for a review."""
    token = authorization.removeprefix("Bearer ").strip()
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.token == token))
        dev = result.scalar_one_or_none()
        if not dev:
            raise HTTPException(401, "Invalid token")
        rq = await db.execute(select(ReviewLog).where(
            ReviewLog.id == review_id,
            ReviewLog.developer_id == dev.id
        ))
        review = rq.scalar_one_or_none()
        if not review:
            raise HTTPException(404, "Review not found")
    return {"report": review.report_content, "verdict": review.verdict}
