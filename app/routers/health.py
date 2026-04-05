from fastapi import APIRouter

from app.config import settings

router = APIRouter(tags=["health"])


@router.get("/health")
async def health():
    """Liveness / readiness probe endpoint."""
    return {"status": "ok", "environment": settings.environment}


@router.get("/ready")
async def ready():
    """Readiness probe — extend to check downstream services when needed."""
    return {"status": "ready"}
