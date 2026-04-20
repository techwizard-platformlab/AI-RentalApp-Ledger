#!/usr/bin/env bash
# .github/scripts/gcp/ci-rag-api.sh
# GCP-specific registry setup for RAG API CI build
# Outputs image_tags and ar_server to GITHUB_OUTPUT
#
# Required env vars:
#   ENVIRONMENT     dev | qa | uat | prod
#   IMAGE_NAME      container image name (e.g. rental-rag-api)
#   GIT_SHA         git commit SHA for image tag
#   GCP_PROJECT_ID
#   GCP_REGION

set -euo pipefail

ENV="${ENVIRONMENT:-dev}"
IMAGE="${IMAGE_NAME:-rental-rag-api}"
SHA="${GIT_SHA:-latest}"
PROJECT="${GCP_PROJECT_ID}"
REGION="${GCP_REGION:-us-central1}"

log() { echo "[gcp/ci-rag-api] $*"; }
die() { echo "[gcp/ci-rag-api] ERROR: $*" >&2; exit 1; }

# ── Resolve Artifact Registry ─────────────────────────────────────────────────
AR_SERVER="${REGION}-docker.pkg.dev"
AR_REPO="${AR_SERVER}/${PROJECT}/rentalapp"

log "Artifact Registry: ${AR_REPO}"

# ── Auth Docker with AR ────────────────────────────────────────────────────────
log "Configuring Docker auth for Artifact Registry…"
gcloud auth configure-docker "${AR_SERVER}" --quiet

# ── Build image tags ──────────────────────────────────────────────────────────
TAG_LATEST="${AR_REPO}/${IMAGE}:latest"
TAG_SHA="${AR_REPO}/${IMAGE}:${SHA}"
TAG_ENV="${AR_REPO}/${IMAGE}:${ENV}-latest"

IMAGE_TAGS="${TAG_LATEST}
${TAG_SHA}
${TAG_ENV}"

log "Image tags:"
echo "${IMAGE_TAGS}" | sed 's/^/  /'

# ── Write outputs ─────────────────────────────────────────────────────────────
{
  echo "ar_server=${AR_SERVER}"
  echo "ar_repo=${AR_REPO}"
  # Multi-line output requires delimiter syntax
  echo "image_tags<<EOF"
  echo "${IMAGE_TAGS}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"

log "Done — registry setup complete"
