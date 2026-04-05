import httpx
from fastapi import APIRouter, HTTPException

from app.config import settings

router = APIRouter()


@router.get("/")
async def list_ledger_entries():
    """Proxy to ledger-service."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(f"{settings.ledger_service_url}/ledger")
            resp.raise_for_status()
            return resp.json()
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail=f"ledger-service unavailable: {exc}") from exc


@router.get("/{entry_id}")
async def get_ledger_entry(entry_id: str):
    """Proxy a single ledger entry to ledger-service."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(f"{settings.ledger_service_url}/ledger/{entry_id}")
            resp.raise_for_status()
            return resp.json()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail=f"ledger-service unavailable: {exc}") from exc
