"""
indexer.py — Embed rental Documents and store in ChromaDB.
Runs as a Kubernetes CronJob every hour.
Incremental: only embeds records updated since last run.
"""

import json
import logging
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import chromadb
from chromadb.config import Settings
from sentence_transformers import SentenceTransformer

from extract_data import Document, extract_all_documents

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stdout)
log = logging.getLogger(__name__)

CHROMA_PATH   = os.environ.get("CHROMA_PATH", "/data/chroma")
COLLECTION    = os.environ.get("CHROMA_COLLECTION", "rental_ledger")
EMBED_MODEL   = os.environ.get("EMBED_MODEL", "all-MiniLM-L6-v2")
WATERMARK_FILE = Path(os.environ.get("WATERMARK_PATH", "/data/last_indexed.json"))
BATCH_SIZE    = int(os.environ.get("BATCH_SIZE", "50"))


def _load_watermark() -> datetime | None:
    """Return the last indexed timestamp, or None for full reindex."""
    if WATERMARK_FILE.exists():
        data = json.loads(WATERMARK_FILE.read_text())
        return datetime.fromisoformat(data["last_indexed"])
    return None


def _save_watermark(ts: datetime) -> None:
    WATERMARK_FILE.parent.mkdir(parents=True, exist_ok=True)
    WATERMARK_FILE.write_text(json.dumps({"last_indexed": ts.isoformat()}))


def get_chroma_collection() -> chromadb.Collection:
    client = chromadb.PersistentClient(
        path=CHROMA_PATH,
        settings=Settings(anonymized_telemetry=False),
    )
    return client.get_or_create_collection(
        name=COLLECTION,
        metadata={"hnsw:space": "cosine"},
    )


def embed_documents(documents: list[Document]) -> None:
    """Embed documents and upsert into ChromaDB. Incremental via watermark."""
    if not documents:
        log.info("No documents to embed.")
        return

    log.info("Loading embedding model: %s", EMBED_MODEL)
    model = SentenceTransformer(EMBED_MODEL)
    collection = get_chroma_collection()

    # Process in batches to avoid OOM on constrained nodes
    total = 0
    for i in range(0, len(documents), BATCH_SIZE):
        batch = documents[i : i + BATCH_SIZE]
        texts = [d.text for d in batch]
        ids   = [f"{d.metadata['table']}_{d.metadata['id']}" for d in batch]
        metas = [d.metadata for d in batch]

        log.info("Embedding batch %d/%d (%d docs)...", i // BATCH_SIZE + 1, -(-len(documents) // BATCH_SIZE), len(batch))
        embeddings = model.encode(texts, show_progress_bar=False).tolist()

        collection.upsert(
            ids=ids,
            documents=texts,
            embeddings=embeddings,
            metadatas=metas,
        )
        total += len(batch)

    log.info("Indexed %d documents into ChromaDB collection '%s'.", total, COLLECTION)


def run() -> None:
    start = datetime.now(timezone.utc)
    since = _load_watermark()
    mode = "incremental" if since else "full"
    log.info("Starting %s indexing run (since=%s).", mode, since)

    documents = extract_all_documents(since=since)
    log.info("Extracted %d documents from PostgreSQL.", len(documents))

    embed_documents(documents)
    _save_watermark(start)
    log.info("Indexing complete. Watermark saved: %s", start.isoformat())


if __name__ == "__main__":
    run()
