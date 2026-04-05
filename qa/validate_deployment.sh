#!/usr/bin/env bash
# validate_deployment.sh — Post-deployment smoke validation for rentalAppLedger
#
# Usage:
#   ./validate_deployment.sh --cloud azure --env dev --notify discord
#   ./validate_deployment.sh --cloud gcp   --env qa
#
# Exit codes:
#   0 = all critical checks passed
#   1 = one or more critical checks failed
#
# Triggered from:
#   - GitHub Actions post-deploy job
#   - ArgoCD PostSync resource hook (see argocd-postsync-hook.yaml)

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
CLOUD="azure"
ENV="dev"
NOTIFY="discord"
NAMESPACE="rental-dev"
GATEWAY_URL="${AZURE_GATEWAY_URL:-http://api-gateway.rental-dev.svc.cluster.local:80}"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK_URL:-}"
DOMAIN="${TLS_DOMAIN:-rental-app.example.com}"

# ── Counters ──────────────────────────────────────────────────────────────────
PASSED=0
FAILED=0
WARNINGS=0

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  [OK]${NC}   $*"; ((PASSED++));   }
fail() { echo -e "${RED}  [FAIL]${NC} $*"; ((FAILED++));     }
warn() { echo -e "${YELLOW}  [WARN]${NC} $*"; ((WARNINGS++)); }
info() { echo -e "  [INFO] $*"; }

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --cloud)   CLOUD="$2";  shift 2 ;;
    --env)     ENV="$2";    shift 2 ;;
    --notify)  NOTIFY="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

NAMESPACE="rental-${ENV}"
if [[ "$CLOUD" == "gcp" ]]; then
  GATEWAY_URL="${GCP_GATEWAY_URL:-http://api-gateway.rental-${ENV}.svc.cluster.local:80}"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " rentalAppLedger Post-Deployment Validation"
echo " Cloud: ${CLOUD}  |  Env: ${ENV}  |  Namespace: ${NAMESPACE}"
echo "═══════════════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Kubernetes Health Checks
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Section 1: Kubernetes Health Checks"

# Check all pods are Running
NOT_RUNNING=$(kubectl get pods -n "${NAMESPACE}" \
  --field-selector='status.phase!=Running,status.phase!=Succeeded' \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
if [[ -z "${NOT_RUNNING}" ]]; then
  ok "All pods in '${NAMESPACE}' are Running or Succeeded"
else
  fail "Pods not Running: ${NOT_RUNNING}"
fi

# Check for CrashLoopBackOff
CRASHLOOP=$(kubectl get pods -n "${NAMESPACE}" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{end}{"\n"}{end}' \
  2>/dev/null | grep -c "CrashLoopBackOff" || true)
if [[ "${CRASHLOOP}" -eq 0 ]]; then
  ok "No CrashLoopBackOff pods"
else
  fail "${CRASHLOOP} pod(s) in CrashLoopBackOff"
fi

# Check deployment replicas
MISMATCHED=0
while IFS= read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  desired=$(echo "$line" | awk '{print $2}')
  available=$(echo "$line" | awk '{print $4}')
  if [[ "${desired}" != "${available}" ]]; then
    fail "Deployment '${name}': desired=${desired} available=${available}"
    ((MISMATCHED++))
  fi
done < <(kubectl get deployments -n "${NAMESPACE}" \
  --no-headers -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas' 2>/dev/null || true)
[[ "${MISMATCHED}" -eq 0 ]] && ok "All deployments have desired replicas available"

# Check services have endpoints
for svc in api-gateway rental-service ledger-service notification-service; do
  ENDPOINTS=$(kubectl get endpoints "${svc}" -n "${NAMESPACE}" \
    -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
  if [[ -n "${ENDPOINTS}" ]]; then
    ok "Service '${svc}' has endpoints"
  else
    fail "Service '${svc}' has NO endpoints (pods not ready?)"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# 2. API Smoke Tests
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Section 2: API Smoke Tests"

SERVICES=(
  "api-gateway|${GATEWAY_URL}/health"
  "rental-service|http://rental-service.${NAMESPACE}.svc.cluster.local:8001/health"
  "ledger-service|http://ledger-service.${NAMESPACE}.svc.cluster.local:8002/health"
  "notification-service|http://notification-service.${NAMESPACE}.svc.cluster.local:8003/health"
)

for entry in "${SERVICES[@]}"; do
  svc="${entry%%|*}"
  url="${entry##*|}"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${url}" 2>/dev/null || echo "000")
  TIME_MS=$(curl -s -o /dev/null -w "%{time_total}" --max-time 3 "${url}" 2>/dev/null | awk '{printf "%d", $1*1000}' || echo "9999")
  if [[ "${HTTP_CODE}" == "200" ]]; then
    ok "${svc} /health → ${HTTP_CODE} (${TIME_MS}ms)"
  else
    fail "${svc} /health → ${HTTP_CODE} (expected 200)"
  fi
  if [[ "${TIME_MS}" -gt 3000 ]]; then
    warn "${svc} response time ${TIME_MS}ms > 3000ms"
  fi
done

# Rentals API (auth required = 200 or 401 = OK)
RENTALS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${GATEWAY_URL}/api/v1/rentals" 2>/dev/null || echo "000")
if [[ "${RENTALS_CODE}" =~ ^(200|401)$ ]]; then
  ok "GET /api/v1/rentals → ${RENTALS_CODE} (expected 200 or 401)"
else
  fail "GET /api/v1/rentals → ${RENTALS_CODE} (expected 200 or 401)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. TLS Certificate Check
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Section 3: TLS Certificate Checks"

if command -v openssl &>/dev/null; then
  CERT_END=$(echo | timeout 5 openssl s_client -connect "${DOMAIN}:443" -servername "${DOMAIN}" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)
  if [[ -n "${CERT_END}" ]]; then
    EXPIRY_EPOCH=$(date -d "${CERT_END}" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "${CERT_END}" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
    if [[ "${DAYS_LEFT}" -gt 14 ]]; then
      ok "TLS cert for ${DOMAIN} valid for ${DAYS_LEFT} more days"
    elif [[ "${DAYS_LEFT}" -gt 0 ]]; then
      warn "TLS cert for ${DOMAIN} expires in ${DAYS_LEFT} days — renew soon"
    else
      fail "TLS cert for ${DOMAIN} has EXPIRED"
    fi
  else
    warn "Could not connect to ${DOMAIN}:443 — skipping TLS check (may be internal cluster)"
  fi
else
  warn "openssl not installed — skipping TLS check"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. Resource Threshold Checks
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Section 4: Resource Threshold Checks"

if kubectl top pods -n "${NAMESPACE}" &>/dev/null; then
  # kubectl top works — check memory
  while IFS= read -r line; do
    pod=$(echo "$line" | awk '{print $1}')
    mem_raw=$(echo "$line" | awk '{print $3}')
    # mem_raw is like "128Mi" or "1024Ki" — basic check: warn if > 450Mi
    mem_mi=$(echo "${mem_raw}" | grep -oP '^\d+' || echo "0")
    unit=$(echo "${mem_raw}" | grep -oP '[A-Za-z]+$' || echo "Mi")
    if [[ "${unit}" == "Gi" ]]; then mem_mi=$((mem_mi * 1024)); fi
    if [[ "${mem_mi}" -gt 450 ]]; then
      warn "Pod '${pod}' memory ${mem_raw} is above 450Mi (approaching 512Mi limit)"
    fi
  done < <(kubectl top pods -n "${NAMESPACE}" --no-headers 2>/dev/null | tail -n +2 || true)
  ok "Memory threshold check complete"
else
  warn "kubectl top not available (metrics-server may not be installed) — skipping resource check"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Istio Health Check
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Section 5: Istio Health"

if kubectl get namespace istio-system &>/dev/null 2>&1; then
  # Check sidecar injection on pods
  PODS_WITHOUT_SIDECAR=$(kubectl get pods -n "${NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].name}{"\n"}{end}' \
    2>/dev/null | grep -vc "istio-proxy" || true)
  if [[ "${PODS_WITHOUT_SIDECAR}" -eq 0 ]]; then
    ok "All pods in ${NAMESPACE} have istio-proxy sidecar"
  else
    warn "${PODS_WITHOUT_SIDECAR} pod(s) missing istio-proxy sidecar"
  fi
else
  info "Istio not installed — skipping Istio checks"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
SUMMARY="{\"cloud\":\"${CLOUD}\",\"env\":\"${ENV}\",\"namespace\":\"${NAMESPACE}\",\"passed\":${PASSED},\"failed\":${FAILED},\"warnings\":${WARNINGS}}"
echo -e " Results: ${GREEN}${PASSED} passed${NC}  ${RED}${FAILED} failed${NC}  ${YELLOW}${WARNINGS} warnings${NC}"
echo " JSON: ${SUMMARY}"
echo "═══════════════════════════════════════════════════════════════"

# Discord notification
if [[ "${NOTIFY}" == "discord" && -n "${DISCORD_WEBHOOK}" ]]; then
  COLOR=$( [[ "${FAILED}" -eq 0 ]] && echo "3066993" || echo "15158332" )
  EMOJI=$( [[ "${FAILED}" -eq 0 ]] && echo "✅" || echo "❌" )
  STATUS=$( [[ "${FAILED}" -eq 0 ]] && echo "PASSED" || echo "FAILED" )
  curl -s -X POST "${DISCORD_WEBHOOK}" \
    -H "Content-Type: application/json" \
    -d "{\"embeds\":[{\"title\":\"${EMOJI} Post-Deploy Validation ${STATUS}\",\"description\":\"Cloud: ${CLOUD} | Env: ${ENV}\",\"color\":${COLOR},\"fields\":[{\"name\":\"Passed\",\"value\":\"${PASSED}\",\"inline\":true},{\"name\":\"Failed\",\"value\":\"${FAILED}\",\"inline\":true},{\"name\":\"Warnings\",\"value\":\"${WARNINGS}\",\"inline\":true}]}]}" \
    > /dev/null
fi

# Exit code
if [[ "${FAILED}" -gt 0 ]]; then
  exit 1
fi
exit 0
