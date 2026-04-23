#!/usr/bin/env bash
# environments/shared/testing/validate_deployment.sh
# Post-deploy validation: checks pods, services, ArgoCD sync, and optionally notifies Discord
#
# Usage:
#   bash environments/shared/testing/validate_deployment.sh \
#     --cloud azure|gcp \
#     --env dev|qa|uat|prod \
#     [--notify discord] \
#     [--namespace rental-dev]

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
CLOUD="azure"
ENV="dev"
NOTIFY=""
NAMESPACE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)     CLOUD="$2";     shift 2 ;;
    --env)       ENV="$2";       shift 2 ;;
    --notify)    NOTIFY="$2";    shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

NAMESPACE="${NAMESPACE:-rental-${ENV}}"
ARGOCD_NS="argocd"
PASS=0
FAIL=0
RESULTS=()

log()  { echo "[validate] $*"; }
pass() { PASS=$((PASS+1)); RESULTS+=("PASS: $*"); echo "  ✓ $*"; }
fail() { FAIL=$((FAIL+1)); RESULTS+=("FAIL: $*"); echo "  ✗ $*"; }

# ── Checks ────────────────────────────────────────────────────────────────────
check_pods() {
  log "Checking pods in namespace ${NAMESPACE}…"
  local not_running
  not_running=$(kubectl get pods -n "${NAMESPACE}" \
    --no-headers 2>/dev/null \
    | grep -v -E "Running|Completed" | wc -l || echo "0")
  if [[ "$not_running" -eq 0 ]]; then
    pass "All pods Running/Completed in ${NAMESPACE}"
  else
    fail "${not_running} pod(s) not Running in ${NAMESPACE}"
    kubectl get pods -n "${NAMESPACE}" | grep -v -E "Running|Completed" || true
  fi
}

check_services() {
  log "Checking services in namespace ${NAMESPACE}…"
  local svc_count
  svc_count=$(kubectl get svc -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l || echo "0")
  if [[ "$svc_count" -gt 0 ]]; then
    pass "${svc_count} service(s) found in ${NAMESPACE}"
  else
    fail "No services found in ${NAMESPACE}"
  fi
}

check_argocd_sync() {
  log "Checking ArgoCD application sync status…"
  local app_name="rentalapp-${ENV}"
  if ! kubectl get application "${app_name}" -n "${ARGOCD_NS}" &>/dev/null; then
    fail "ArgoCD Application ${app_name} not found"
    return
  fi
  local sync_status health_status
  sync_status=$(kubectl get application "${app_name}" -n "${ARGOCD_NS}" \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  health_status=$(kubectl get application "${app_name}" -n "${ARGOCD_NS}" \
    -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

  if [[ "$sync_status" == "Synced" ]]; then
    pass "ArgoCD sync: ${sync_status}"
  else
    fail "ArgoCD sync: ${sync_status} (expected Synced)"
  fi

  if [[ "$health_status" == "Healthy" ]]; then
    pass "ArgoCD health: ${health_status}"
  else
    fail "ArgoCD health: ${health_status} (expected Healthy)"
  fi
}

check_api_gateway() {
  log "Checking API Gateway connectivity…"
  local svc_ip
  svc_ip=$(kubectl get svc api-gateway -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -z "$svc_ip" ]]; then
    svc_ip=$(kubectl get svc api-gateway -n "${NAMESPACE}" \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  fi

  if [[ -z "$svc_ip" ]]; then
    fail "API Gateway has no external IP/hostname assigned"
    return
  fi

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 "http://${svc_ip}:8000/health" 2>/dev/null || echo "000")

  if [[ "$http_code" == "200" ]]; then
    pass "API Gateway /health → HTTP ${http_code}"
  else
    fail "API Gateway /health → HTTP ${http_code} (expected 200)"
  fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo "══════════════════════════════════════════"
  echo "  Validation summary: ${ENV} (${CLOUD})"
  echo "══════════════════════════════════════════"
  for r in "${RESULTS[@]}"; do echo "  ${r}"; done
  echo ""
  echo "  PASS: ${PASS}  FAIL: ${FAIL}"
  echo "══════════════════════════════════════════"
}

notify_discord() {
  local webhook="${DISCORD_WEBHOOK_URL:-}"
  [[ -z "$webhook" ]] && return

  local status_emoji="✅"
  local color=3066993
  if [[ "$FAIL" -gt 0 ]]; then
    status_emoji="❌"
    color=15158332
  fi

  local summary_text
  summary_text=$(printf '%s\n' "${RESULTS[@]}")

  curl -s -X POST "${webhook}" \
    -H "Content-Type: application/json" \
    -d "{
      \"embeds\": [{
        \"title\": \"${status_emoji} Deploy Validation — ${ENV} (${CLOUD})\",
        \"description\": \"\`\`\`\n${summary_text}\n\`\`\`\nPASS: ${PASS}  FAIL: ${FAIL}\",
        \"color\": ${color}
      }]
    }" || log "WARN: Discord notification failed"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  log "Starting validation: cloud=${CLOUD} env=${ENV} namespace=${NAMESPACE}"

  check_pods
  check_services
  check_argocd_sync
  check_api_gateway
  print_summary

  [[ "${NOTIFY}" == "discord" ]] && notify_discord

  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
