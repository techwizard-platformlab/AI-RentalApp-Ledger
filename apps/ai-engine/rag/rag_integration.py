"""
rag_integration.py — Integrates the RAG API into rentalAppLedger's main FastAPI app.
Add to app/main.py:  app.include_router(rag_router)
"""

import os
import time
from collections import defaultdict

import requests
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from prometheus_client import Counter, Histogram, Gauge

# ── Prometheus metrics ────────────────────────────────────────────────────────
rag_query_total = Counter(
    "rag_query_total", "Total RAG queries", ["status"]
)
rag_query_duration = Histogram(
    "rag_query_duration_seconds", "RAG query latency",
    buckets=[0.1, 0.5, 1.0, 2.0, 5.0, 10.0],
)
rag_context_retrieved = Gauge(
    "rag_context_retrieved", "Number of context docs retrieved per query"
)
rag_llm_tokens_used = Counter(
    "rag_llm_tokens_used_total", "Estimated LLM tokens consumed"
)

# ── Config ────────────────────────────────────────────────────────────────────
RAG_SERVICE_URL  = os.environ.get("RAG_SERVICE_URL", "http://rag-api.rental-dev.svc.cluster.local:8080")
RATE_LIMIT_RPM   = int(os.environ.get("RAG_RATE_LIMIT_RPM", "10"))  # per user per minute

# ── Rate limiter (in-memory, sufficient for single-replica dev) ───────────────
_rate_buckets: dict[str, list[float]] = defaultdict(list)


def _check_rate_limit(user_id: str) -> None:
    now = time.time()
    window = 60.0
    bucket = _rate_buckets[user_id]
    # Remove timestamps older than 1 minute
    _rate_buckets[user_id] = [t for t in bucket if now - t < window]
    if len(_rate_buckets[user_id]) >= RATE_LIMIT_RPM:
        raise HTTPException(
            status_code=429,
            detail=f"Rate limit exceeded: {RATE_LIMIT_RPM} requests/minute. Please wait."
        )
    _rate_buckets[user_id].append(now)


# ── Router ────────────────────────────────────────────────────────────────────
rag_router = APIRouter(prefix="/assistant", tags=["RAG Assistant"])


class AssistantResponse(BaseModel):
    answer: str
    sources_count: int
    sql_hint: str | None
    latency_ms: float


@rag_router.get("/query", response_model=AssistantResponse)
async def assistant_query(q: str, request: Request):
    """
    Natural language query over rental data.
    Rate limited: 10 requests/minute per client IP.
    """
    client_ip = request.client.host if request.client else "unknown"
    _check_rate_limit(client_ip)

    t0 = time.perf_counter()
    try:
        resp = requests.post(
            f"{RAG_SERVICE_URL}/query",
            json={"question": q, "top_k": 5},
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()

        latency = (time.perf_counter() - t0) * 1000
        sources_count = len(data.get("sources", []))

        # Update metrics
        rag_query_total.labels(status="success").inc()
        rag_query_duration.observe(latency / 1000)
        rag_context_retrieved.set(sources_count)
        # Rough token estimate: ~1.3 tokens/word
        rag_llm_tokens_used.inc(len(data.get("answer", "").split()) * 1.3)

        return AssistantResponse(
            answer=data["answer"],
            sources_count=sources_count,
            sql_hint=data.get("sql_hint"),
            latency_ms=round(latency, 2),
        )
    except requests.RequestException as e:
        rag_query_total.labels(status="error").inc()
        raise HTTPException(status_code=503, detail=f"RAG service unavailable: {e}")
