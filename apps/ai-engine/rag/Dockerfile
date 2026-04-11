FROM python:3.11-slim AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN python -m venv /opt/venv && /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    # Explicitly install PyTorch CPU wheels to prevent a massive 2GB+ CUDA download
    /opt/venv/bin/pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu && \
    /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 curl && rm -rf /var/lib/apt/lists/*
# Create appuser with a real home directory so HuggingFace cache dir is writable
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --create-home appuser && \
    mkdir -p /home/appuser/.cache/huggingface /data && \
    chown -R appuser:appgroup /home/appuser /data
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" \
    HF_HOME="/home/appuser/.cache/huggingface" \
    TRANSFORMERS_CACHE="/home/appuser/.cache/huggingface"
COPY extract_data.py indexer.py api.py ./
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD curl -f http://localhost:8080/health || exit 1
CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8080"]
