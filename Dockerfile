# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Builder
# Install dependencies in a virtualenv so they can be copied cleanly.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build deps (only in builder stage)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for layer caching
COPY requirements.txt .

# Create virtualenv and install packages
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Runtime
# Minimal image — no build tools, non-root user, read-only filesystem.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.11-slim AS runtime

# Install only runtime system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --no-create-home --shell /bin/false appuser

WORKDIR /app

# Copy virtualenv from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application source
COPY --chown=appuser:appgroup app/ ./app/

# Switch to non-root user
USER appuser

# Expose FastAPI default port
EXPOSE 8000

# Health check (matches Kubernetes readiness/liveness probes)
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run with uvicorn; --no-access-log reduces noise (use structured logging in app)
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
