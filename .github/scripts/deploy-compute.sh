#!/usr/bin/env bash
# .github/scripts/deploy-compute.sh
# Re-deploy compute resources after a destroy session.
#
# Applies cluster + networking only. Persistent resources (registry, database,
# secrets store) are already running and are NOT touched.
#
# Usage:
#   .github/scripts/deploy-compute.sh [azure|gcp|both] [dev|qa|uat|prod]
#
# Examples:
#   .github/scripts/deploy-compute.sh azure dev
#   .github/scripts/deploy-compute.sh both dev

set -euo pipefail

CLOUD="${1:-azure}"
ENV="${2:-dev}"

AZURE_DIR="infrastructure/azure/environments/${ENV}"
GCP_DIR="infrastructure/gcp/environments/${ENV}"

deploy_azure() {
  echo "==> Azure: deploying compute for ${ENV}..."
  cd "$AZURE_DIR"
  terraform apply -auto-approve \
    -target=module.vnet \
    -target=module.subnet \
    -target=module.security_group \
    -target=module.load_balancer \
    -target=module.aks
  echo "==> Azure compute deployed."
  cd - > /dev/null
}

deploy_gcp() {
  echo "==> GCP: deploying compute for ${ENV}..."
  cd "$GCP_DIR"
  terraform apply -auto-approve \
    -target=module.vpc \
    -target=module.nat \
    -target=module.gke
  echo "==> GCP compute deployed."
  cd - > /dev/null
}

case "$CLOUD" in
  azure) deploy_azure ;;
  gcp)   deploy_gcp   ;;
  both)  deploy_azure; deploy_gcp ;;
  *)
    echo "ERROR: unknown cloud '${CLOUD}'. Use: azure | gcp | both"
    exit 1
    ;;
esac

echo ""
echo "Done. Compute is running for ${ENV}."
echo "Stop billing after your session: .github/scripts/destroy-compute.sh ${CLOUD} ${ENV}"
