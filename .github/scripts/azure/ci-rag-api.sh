#!/usr/bin/env bash
# .github/scripts/azure/ci-rag-api.sh
# Azure-specific registry setup for RAG API CI build
# Outputs image_tags and acr_server to GITHUB_OUTPUT
#
# Required env vars:
#   ENVIRONMENT     dev | qa | uat | prod
#   IMAGE_NAME      container image name (e.g. rental-rag-api)
#   GIT_SHA         git commit SHA for image tag
#   PLATFORM_KV_NAME  Key Vault name (e.g. techwizard-plt-kv)
#   AZURE_SHARED_RG   Resource group containing ACR

set -euo pipefail

ENV="${ENVIRONMENT:-dev}"
IMAGE="${IMAGE_NAME:-rental-rag-api}"
SHA="${GIT_SHA:-latest}"
KV="${PLATFORM_KV_NAME:-techwizard-plt-kv}"
RG="${AZURE_SHARED_RG:-my-Rental-App}"

log() { echo "[azure/ci-rag-api] $*"; }
die() { echo "[azure/ci-rag-api] ERROR: $*" >&2; exit 1; }

# ── Resolve ACR ───────────────────────────────────────────────────────────────
log "Resolving ACR login server…"
ACR_SERVER=$(az keyvault secret show \
  --vault-name "${KV}" \
  --name "acr-login-server" \
  --query value -o tsv 2>/dev/null || \
az acr list \
  --resource-group "${RG}" \
  --query "[0].loginServer" -o tsv)

[[ -z "$ACR_SERVER" ]] && die "Could not resolve ACR login server from Key Vault or resource group ${RG}"

ACR_NAME=$(echo "${ACR_SERVER}" | cut -d'.' -f1)
log "ACR: ${ACR_SERVER} (name: ${ACR_NAME})"

# ── ACR login ─────────────────────────────────────────────────────────────────
log "Logging in to ACR…"
az acr login --name "${ACR_NAME}"

# ── Build image tags ──────────────────────────────────────────────────────────
TAG_LATEST="${ACR_SERVER}/${IMAGE}:latest"
TAG_SHA="${ACR_SERVER}/${IMAGE}:${SHA}"
TAG_ENV="${ACR_SERVER}/${IMAGE}:${ENV}-latest"

IMAGE_TAGS="${TAG_LATEST}
${TAG_SHA}
${TAG_ENV}"

log "Image tags:"
echo "${IMAGE_TAGS}" | sed 's/^/  /'

# ── Write outputs ─────────────────────────────────────────────────────────────
{
  echo "acr_server=${ACR_SERVER}"
  echo "acr_name=${ACR_NAME}"
  # Multi-line output requires delimiter syntax
  echo "image_tags<<EOF"
  echo "${IMAGE_TAGS}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"

log "Done — registry setup complete"
