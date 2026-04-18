"""
api.py — FastAPI RAG query API for rentalAppLedger.
Endpoints: POST /query, GET /health, GET /stats
LLM provider: openai (env: LLM_PROVIDER)
"""

import os
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any

import requests
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

import chromadb
from chromadb.config import Settings
from sentence_transformers import SentenceTransformer

# ── Config ────────────────────────────────────────────────────────────────────
CHROMA_PATH  = os.environ.get("CHROMA_PATH", "/data/chroma")
COLLECTION   = os.environ.get("CHROMA_COLLECTION", "rental_ledger")
EMBED_MODEL  = os.environ.get("EMBED_MODEL", "all-MiniLM-L6-v2")
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
OPENAI_MODEL   = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")

# ── State ─────────────────────────────────────────────────────────────────────
_state: dict[str, Any] = {}

SYSTEM_PROMPT = (
    "You are a rental ledger assistant for rentalAppLedger. "
    "Answer questions using ONLY the context provided below. "
    "If the context does not contain the answer, say exactly: "
    "'I don't have data on that. Please check the database directly.' "
    "Never invent tenant names, amounts, or dates."
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    _state["model"] = SentenceTransformer(EMBED_MODEL)
    client = chromadb.PersistentClient(
        path=CHROMA_PATH,
        settings=Settings(anonymized_telemetry=False),
    )
    _state["collection"] = client.get_or_create_collection(COLLECTION)
    _state["query_count"] = 0
    _state["started_at"] = datetime.now(timezone.utc).isoformat()
    yield
    _state.clear()


app = FastAPI(title="rentalAppLedger RAG API", lifespan=lifespan)


# ── Schemas ───────────────────────────────────────────────────────────────────
class QueryRequest(BaseModel):
    question: str = Field(..., min_length=3, max_length=500)
    top_k: int = Field(default=5, ge=1, le=20)


class SourceDoc(BaseModel):
    text: str
    metadata: dict


class QueryResponse(BaseModel):
    answer: str
    sources: list[SourceDoc]
    sql_hint: str | None = None
    latency_ms: float


# ── LLM helpers ───────────────────────────────────────────────────────────────
def _build_prompt(question: str, context_chunks: list[str]) -> str:
    context = "\n---\n".join(context_chunks)
    return f"Context:\n{context}\n\nQuestion: {question}\n\nAnswer:"


def _call_openai(prompt: str) -> str:
    resp = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers={"Authorization": f"Bearer {OPENAI_API_KEY}", "Content-Type": "application/json"},
        json={
            "model": OPENAI_MODEL,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
        },
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


def _generate(question: str, context_chunks: list[str]) -> str:
    if not context_chunks:
        return "I don't have data on that. Please check the database directly."
    return _call_openai(_build_prompt(question, context_chunks))


def _sql_hint(question: str) -> str | None:
    """Very basic keyword-based SQL hint — no LLM call needed."""
    q = question.lower()
    if "overdue" in q:
        return "SELECT * FROM payments WHERE status = 'overdue' ORDER BY payment_date;"
    if "tenant" in q and ("pay" in q or "amount" in q):
        return "SELECT t.full_name, SUM(p.amount) FROM payments p JOIN leases l ON p.lease_id=l.id JOIN tenants t ON l.tenant_id=t.id GROUP BY t.full_name;"
    if "lease" in q or "active" in q:
        return "SELECT * FROM leases WHERE status = 'active';"
    return None


# ── Endpoints ─────────────────────────────────────────────────────────────────
@app.post("/query", response_model=QueryResponse)
async def query(req: QueryRequest):
    t0 = time.perf_counter()
    _state["query_count"] = _state.get("query_count", 0) + 1

    # Embed the question
    embedding = _state["model"].encode(req.question).tolist()

    # Retrieve top-k chunks from ChromaDB
    results = _state["collection"].query(
        query_embeddings=[embedding],
        n_results=req.top_k,
        include=["documents", "metadatas", "distances"],
    )

    docs = results["documents"][0] if results["documents"] else []
    metas = results["metadatas"][0] if results["metadatas"] else []
    sources = [SourceDoc(text=d, metadata=m) for d, m in zip(docs, metas)]

    answer = _generate(req.question, docs)
    latency = (time.perf_counter() - t0) * 1000

    return QueryResponse(
        answer=answer,
        sources=sources,
        sql_hint=_sql_hint(req.question),
        latency_ms=round(latency, 2),
    )


@app.get("/health")
async def health():
    if "model" not in _state or "collection" not in _state:
        raise HTTPException(status_code=503, detail="starting up")
    return {"status": "healthy", "provider": LLM_PROVIDER}


@app.get("/stats")
async def stats():
    count = _state["collection"].count() if "collection" in _state else 0
    return {
        "total_documents": count,
        "query_count": _state.get("query_count", 0),
        "started_at": _state.get("started_at"),
        "llm_provider": LLM_PROVIDER,
        "embed_model": EMBED_MODEL,
    }
