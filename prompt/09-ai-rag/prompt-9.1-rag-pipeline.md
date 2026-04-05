# Prompt 9.1 - RAG System: PostgreSQL + Embeddings + Vector Store

```
Act as a Python AI engineer specialising in RAG (Retrieval-Augmented Generation).

CONTEXT:
- App: rentalAppLedger - manages rental transactions and ledger entries
- Database: PostgreSQL (on AKS / GKE via Kubernetes)
- Goal: natural language queries over rental data
  e.g. "Show me all overdue payments for tenant John" -> SQL + LLM response
- LLM: use cheapest/free option:
  1. Ollama (local - nomic-embed-text for embeddings, llama3.2 for generation)
  2. Groq free tier (llama3-8b-8192)
- Vector store: use simple file-based (ChromaDB - no extra cost)

TASK:
Build complete RAG pipeline:

### Component 1: Data Extractor (extract_data.py)
```python
# Extract rental data from PostgreSQL
# Tables assumed: tenants, properties, payments, leases, ledger_entries

def extract_all_documents() -> list[Document]:
    """
    Convert DB rows to text documents for embedding:
    - Each payment: "Tenant {name} paid INR {amount} on {date} for property {addr}. Status: {status}"
    - Each lease: "Lease for {tenant} at {property}: {start} to {end}. Rent: INR {amount}/month"
    - Each ledger entry: full text description
    Returns list of Document(text, metadata={table, id, date, tenant_id})
    """
```

### Component 2: Embedding + Indexer (indexer.py)
```python
def embed_documents(documents: list[Document]) -> None:
    """
    - Use sentence-transformers (all-MiniLM-L6-v2) for free local embeddings
    - Store in ChromaDB (persistent, local file)
    - Incremental: only embed new/changed records (check updated_at)
    - Run as Kubernetes CronJob: every 1 hour
    """
```

### Component 3: FastAPI Query API (api.py)
```python
# Endpoints:

POST /query
{
  "question": "Which tenants have overdue payments this month?",
  "top_k": 5
}
-> {
  "answer": "LLM-generated natural language answer",
  "sources": [{"text": "...", "metadata": {...}}],
  "sql_hint": "SELECT * FROM payments WHERE ..."  # bonus: suggest SQL
}

GET /health
GET /stats  # total documents, last indexed, query count
```

### Component 4: LLM Integration
- System prompt: "You are a rental ledger assistant. Answer using ONLY the provided context."
- Include retrieved chunks as context
- If no relevant context found: "I don't have data on that. Please check the database directly."
- Never hallucinate tenant names or amounts

### Kubernetes Deployment:
- Deployment: rag-api (2 replicas in qa)
- CronJob: rag-indexer (hourly)
- PVC: 1Gi for ChromaDB storage (ReadWriteOnce)
- NOTE: file-based vector stores are single-writer; avoid concurrent index writes.
- ConfigMap: DB connection, LLM provider
- Secret: DB password (from KeyVault/Secret Manager)

INCLUDE:
- requirements.txt (fastapi, chromadb, sentence-transformers, psycopg2, sqlalchemy)
- Dockerfile
- Kubernetes manifests
- Sample queries + expected outputs
- How to switch LLM provider (env variable: LLM_PROVIDER=ollama|groq|claude)

OUTPUT: All Python files (full code) + Kubernetes manifests + README
```
