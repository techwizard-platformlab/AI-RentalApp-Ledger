#!/usr/bin/env bash
# .github/scripts/deploy-compute.sh
# Quick wrapper: trigger compute-only Terraform apply via GitHub Actions
# Usage: bash .github/scripts/deploy-compute.sh <cloud> <env>
#   cloud: azure | gcp | both
#   env:   dev   | qa  | uat | prod
#
# Requires: gh CLI authenticated (gh auth login)

set -euo pipefail

CLOUD="${1:-azure}"
ENV="${2:-dev}"
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"

log() { echo "[deploy-compute] $*"; }
die() { echo "[deploy-compute] ERROR: $*" >&2; exit 1; }

[[ -z "$REPO" ]] && die "Could not determine repository. Set GITHUB_REPOSITORY or run inside a GitHub-authenticated shell."

log "Triggering Terraform apply (compute-only) for cloud=${CLOUD} env=${ENV} repo=${REPO}…"

gh workflow run terraform.yml \
  --repo "${REPO}" \
  --field target_env="${ENV}" \
  --field cloud="${CLOUD}" \
  --field action="apply" \
  --field scope="compute-only"

log "Workflow dispatched. Monitor at: https://github.com/${REPO}/actions"
