import time

from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import settings
from app.routers import health, rentals, ledger

app = FastAPI(
    title="rentalAppLedger API Gateway",
    version="1.0.0",
    description="API Gateway for the rentalAppLedger microservices",
)

# Prometheus metrics at /metrics
Instrumentator().instrument(app).expose(app)

# Routers
app.include_router(health.router)
app.include_router(rentals.router, prefix="/api/v1/rentals", tags=["rentals"])
app.include_router(ledger.router, prefix="/api/v1/ledger", tags=["ledger"])

# Track startup time
_start_time = time.time()


@app.get("/", include_in_schema=False)
async def root():
    return {
        "service": "rentalAppLedger API Gateway",
        "version": "1.0.0",
        "environment": settings.environment,
        "uptime_seconds": round(time.time() - _start_time, 2),
    }
