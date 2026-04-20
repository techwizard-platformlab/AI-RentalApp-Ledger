#!/usr/bin/env bash
# .github/scripts/gcp/ci-rag-api.sh
# GCP-specific: configure Artifact Registry auth and resolve image tags.
#
# Required env vars:
#   GCP_PROJECT_ID     — GCP project ID
#   GCP_REGION         — GCP region (e.g. us-central1) [default: us-central1]
#   ENV                — target environment (dev | qa | uat | prod) [default: dev]
#   IMAGE_NAME         — container image name [default: rental-rag-api]
#   IMAGE_TAG          — primary tag (e.g. git SHA)  [default: latest]
#   GITHUB_OUTPUT      — set by GitHub Actions runner
#   GITHUB_ENV         — set by GitHub Actions runner

set -euo pipefail

ENV="${ENV:-dev}"
IMAGE_NAME="${IMAGE_NAME:-rental-rag-api}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_REGION="${GCP_REGION:-us-central1}"

# ── Fetch Discord webhook from Secret Manager ────────────────────────────────
fetch_discord_webhook() {
  if [ -z "$GCP_PROJECT_ID" ]; then
    echo "GCP_PROJECT_ID not set — skipping Discord webhook fetch"
    return 0
  fi

  local discord
  discord=$(gcloud secrets versions access latest \
    --secret="discord-webhook-url" \
    --project="$GCP_PROJECT_ID" 2>/dev/null || true)

  if [ -n "$discord" ]; then
    echo "::add-mask::$discord"
    echo "DISCORD_WEBHOOK_URL=$discord" >> "$GITHUB_ENV"
  fi
}

# ── Resolve Artifact Registry repository URL ─────────────────────────────────
get_registry_url() {
  if [ -z "$GCP_PROJECT_ID" ]; then
    echo "::error::GCP_PROJECT_ID is required"
    exit 1
  fi

  # Pattern: <region>-docker.pkg.dev/<project>/<repo-name>
  # Repo name convention: rental-<env>
  local registry="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/rental-${ENV}"
  echo "registry_url=$registry" >> "$GITHUB_OUTPUT"
  echo "Artifact Registry: $registry"
}

# ── Configure Docker auth for Artifact Registry ──────────────────────────────
configure_docker_auth() {
  gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet
}

# ── Output full image tags for docker/build-push-action ─────────────────────
output_tags() {
  local registry
  registry=$(grep "^registry_url=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2)

  echo "image_tags=${registry}/${IMAGE_NAME}:${IMAGE_TAG}
${registry}/${IMAGE_NAME}:latest" >> "$GITHUB_OUTPUT"
  echo "cache_ref=${registry}/${IMAGE_NAME}:buildcache" >> "$GITHUB_OUTPUT"
}

# ── Main ─────────────────────────────────────────────────────────────────────
echo "==> GCP CI RAG API: ENV=$ENV PROJECT=$GCP_PROJECT_ID REGION=$GCP_REGION IMAGE=$IMAGE_NAME:$IMAGE_TAG"
fetch_discord_webhook
get_registry_url
configure_docker_auth
output_tags
echo "==> GCP CI setup complete"
