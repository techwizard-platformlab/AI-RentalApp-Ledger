import httpx
from fastapi import APIRouter, HTTPException

from app.config import settings

router = APIRouter()


@router.get("/")
async def list_rentals():
    """Proxy to rental-service."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(f"{settings.rental_service_url}/rentals")
            resp.raise_for_status()
            return resp.json()
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail=f"rental-service unavailable: {exc}") from exc


@router.get("/{rental_id}")
async def get_rental(rental_id: str):
    """Proxy a single rental to rental-service."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(f"{settings.rental_service_url}/rentals/{rental_id}")
            resp.raise_for_status()
            return resp.json()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail=f"rental-service unavailable: {exc}") from exc
