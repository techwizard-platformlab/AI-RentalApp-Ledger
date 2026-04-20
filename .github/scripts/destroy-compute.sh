#!/usr/bin/env bash
# .github/scripts/destroy-compute.sh
# Stop billing after a session by destroying compute resources only.
#
# Destroys cluster + networking. Keeps registry, database, secrets store
# (cheap persistent resources — data remains safe).
#
# Usage:
#   .github/scripts/destroy-compute.sh [azure|gcp|both] [dev|qa|uat|prod]
#
# Examples:
#   .github/scripts/destroy-compute.sh azure dev
#   .github/scripts/destroy-compute.sh both dev
#
# After running: data is safe, images in registry are intact.
# Re-deploy later: .github/scripts/deploy-compute.sh

set -euo pipefail

CLOUD="${1:-azure}"
ENV="${2:-dev}"

AZURE_DIR="infrastructure/azure/environments/${ENV}"
GCP_DIR="infrastructure/gcp/environments/${ENV}"

confirm() {
  echo ""
  echo "  Scope : compute-only (${CLOUD})"
  echo "  Env   : ${ENV}"
  echo "  Keeps : Container Registry, Database, Secrets Store, Storage"
  echo ""
  read -r -p "  Type '${ENV}' to confirm: " answer
  if [ "$answer" != "$ENV" ]; then
    echo "Aborted."
    exit 1
  fi
}

destroy_azure() {
  echo "==> Azure: destroying compute in ${ENV}..."
  cd "$AZURE_DIR"
  terraform destroy -auto-approve \
    -target=module.aks \
    -target=module.load_balancer \
    -target=module.security_group \
    -target=module.subnet \
    -target=module.vnet
  echo "==> Azure compute destroyed. ACR and SQL are still running."
  cd - > /dev/null
}

destroy_gcp() {
  echo "==> GCP: destroying compute in ${ENV}..."
  cd "$GCP_DIR"
  terraform destroy -auto-approve \
    -target=module.gke \
    -target=module.nat \
    -target=module.vpc
  echo "==> GCP compute destroyed. Artifact Registry and Cloud SQL are still running."
  cd - > /dev/null
}

confirm

case "$CLOUD" in
  azure) destroy_azure ;;
  gcp)   destroy_gcp   ;;
  both)  destroy_azure; destroy_gcp ;;
  *)
    echo "ERROR: unknown cloud '${CLOUD}'. Use: azure | gcp | both"
    exit 1
    ;;
esac

echo ""
echo "Done. Compute billing stopped for ${ENV}."
echo "Re-deploy when ready: .github/scripts/deploy-compute.sh ${CLOUD} ${ENV}"
