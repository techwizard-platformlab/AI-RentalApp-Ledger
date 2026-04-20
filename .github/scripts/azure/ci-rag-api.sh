#!/usr/bin/env bash
# .github/scripts/azure/ci-rag-api.sh
# Azure-specific: login to ACR and push the RAG API container image.
#
# Required env vars:
#   AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID (set via OIDC login)
#   PLATFORM_KV_NAME   — platform Key Vault name (optional; falls back to tag discovery)
#   ENV                — target environment (dev | qa | uat | prod) [default: dev]
#   IMAGE_NAME         — container image name [default: rental-rag-api]
#   IMAGE_TAG          — primary tag (e.g. git SHA)  [default: latest]
#   GITHUB_OUTPUT      — set by GitHub Actions runner

set -euo pipefail

ENV="${ENV:-dev}"
IMAGE_NAME="${IMAGE_NAME:-rental-rag-api}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# ── Discover platform Key Vault ──────────────────────────────────────────────
platform_kv() {
  local kv="${PLATFORM_KV_NAME:-}"
  if [ -z "$kv" ]; then
    kv=$(az keyvault list \
      --query "[?tags.role=='platform'].name | [0]" -o tsv 2>/dev/null || true)
  fi
  echo "$kv"
}

# ── Fetch Discord webhook from Key Vault ─────────────────────────────────────
fetch_discord_webhook() {
  local kv
  kv=$(platform_kv)
  if [ -z "$kv" ]; then
    echo "No platform Key Vault found — skipping Discord webhook fetch"
    return 0
  fi
  local discord
  discord=$(az keyvault secret show \
    --vault-name "$kv" \
    --name "discord-webhook-url" \
    --query value -o tsv 2>/dev/null || true)
  if [ -n "$discord" ]; then
    echo "::add-mask::$discord"
    echo "DISCORD_WEBHOOK_URL=$discord" >> "$GITHUB_ENV"
  fi
}

# ── Resolve ACR login server ─────────────────────────────────────────────────
get_acr_server() {
  local kv
  kv=$(platform_kv)
  local acr_server=""

  # 1) Try platform KV secret written by Terraform
  if [ -n "$kv" ]; then
    acr_server=$(az keyvault secret show \
      --vault-name "$kv" \
      --name "acr-login-server" \
      --query value -o tsv 2>/dev/null || true)
  fi

  # 2) Fall back to listing ACR in the env resource group
  if [ -z "$acr_server" ]; then
    local env_rg="rental-app-${ENV}"
    acr_server=$(az acr list \
      --resource-group "$env_rg" \
      --query "[0].loginServer" -o tsv 2>/dev/null || true)
  fi

  if [ -z "$acr_server" ]; then
    echo "::error::Could not resolve ACR login server for ENV=${ENV}"
    exit 1
  fi

  echo "acr_server=$acr_server" >> "$GITHUB_OUTPUT"
  echo "ACR login server: $acr_server"
}

# ── Login to ACR ─────────────────────────────────────────────────────────────
login_acr() {
  local acr_server
  acr_server=$(grep "^acr_server=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2)
  local acr_name
  acr_name=$(echo "$acr_server" | cut -d'.' -f1)
  az acr login --name "$acr_name"
  echo "acr_name=$acr_name" >> "$GITHUB_OUTPUT"
}

# ── Output full image tags for docker/build-push-action ─────────────────────
output_tags() {
  local acr_server
  acr_server=$(grep "^acr_server=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2)
  echo "image_tags=${acr_server}/${IMAGE_NAME}:${IMAGE_TAG}
${acr_server}/${IMAGE_NAME}:latest" >> "$GITHUB_OUTPUT"
  echo "cache_ref=${acr_server}/${IMAGE_NAME}:buildcache" >> "$GITHUB_OUTPUT"
}

# ── Main ─────────────────────────────────────────────────────────────────────
echo "==> Azure CI RAG API: ENV=$ENV IMAGE=$IMAGE_NAME:$IMAGE_TAG"
fetch_discord_webhook
get_acr_server
login_acr
output_tags
echo "==> Azure CI setup complete"
