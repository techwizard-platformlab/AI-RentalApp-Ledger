#!/usr/bin/env bash
# environments/shared/testing/validate_deployment.sh
# Generic post-deployment smoke validation — works for any cloud and environment.
#
# Usage:
#   ./validate_deployment.sh --cloud azure --env dev [--notify discord]
#   ./validate_deployment.sh --cloud gcp   --env qa
#
# Exit codes:
#   0 = all critical checks passed
#   1 = one or more critical checks failed
#
# Triggered by:
#   - GitHub Actions post-deploy job (qa-validate.yml)
#   - ArgoCD PostSync hook (argocd-postsync-hook.yaml in each overlay)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
CLOUD="azure"
ENV="dev"
NOTIFY="none"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK_URL:-}"
DOMAIN="${TLS_DOMAIN:-app.example.com}"

# ── Counters ─────────────────────────────────────────────────────────────────
PASSED=0; FAILED=0; WARNINGS=0

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

# Resolve gateway URL: env var override → cloud default
if [[ "${CLOUD}" == "azure" ]]; then
  GATEWAY_URL="${GATEWAY_URL:-http://api-gateway.${NAMESPACE}.svc.cluster.local:80}"
else
  GATEWAY_URL="${GATEWAY_URL:-http://api-gateway.${NAMESPACE}.svc.cluster.local:80}"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " Post-Deployment Validation"
echo " Cloud: ${CLOUD}  |  Env: ${ENV}  |  Namespace: ${NAMESPACE}"
echo "═══════════════════════════════════════════════════════════════"

# ── 1. Kubernetes Health ──────────────────────────────────────────────────────
echo ""
echo "▶ Section 1: Kubernetes Health"

NOT_RUNNING=$(kubectl get pods -n "${NAMESPACE}" \
  --field-selector='status.phase!=Running,status.phase!=Succeeded' \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
[[ -z "${NOT_RUNNING}" ]] && ok "All pods Running/Succeeded" || fail "Pods not running: ${NOT_RUNNING}"

CRASHLOOP=$(kubectl get pods -n "${NAMESPACE}" \
  -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{end}{end}' \
  2>/dev/null | grep -c "CrashLoopBackOff" || true)
[[ "${CRASHLOOP}" -eq 0 ]] && ok "No CrashLoopBackOff" || fail "${CRASHLOOP} pod(s) in CrashLoopBackOff"

MISMATCHED=0
while IFS= read -r line; do
  name=$(awk '{print $1}' <<< "$line")
  desired=$(awk '{print $2}' <<< "$line")
  avail=$(awk '{print $4}' <<< "$line")
  [[ "${desired}" != "${avail}" ]] && fail "Deployment '${name}': desired=${desired} available=${avail}" && ((MISMATCHED++)) || true
done < <(kubectl get deployments -n "${NAMESPACE}" --no-headers \
  -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas' 2>/dev/null || true)
[[ "${MISMATCHED}" -eq 0 ]] && ok "All deployments have desired replicas"

for svc in api-gateway rental-service ledger-service notification-service; do
  EP=$(kubectl get endpoints "${svc}" -n "${NAMESPACE}" \
    -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
  [[ -n "${EP}" ]] && ok "Service '${svc}' has endpoints" || fail "Service '${svc}' has NO endpoints"
done

# ── 2. API Smoke Tests ────────────────────────────────────────────────────────
echo ""
echo "▶ Section 2: API Smoke Tests"

SERVICES=(
  "api-gateway|${GATEWAY_URL}/health"
  "rental-service|http://rental-service.${NAMESPACE}.svc.cluster.local:8001/health"
  "ledger-service|http://ledger-service.${NAMESPACE}.svc.cluster.local:8002/health"
  "notification-service|http://notification-service.${NAMESPACE}.svc.cluster.local:8003/health"
)

for entry in "${SERVICES[@]}"; do
  svc="${entry%%|*}"; url="${entry##*|}"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${url}" 2>/dev/null || echo "000")
  TIME_MS=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 "${url}" 2>/dev/null | awk '{printf "%d", $1*1000}' || echo "9999")
  [[ "${HTTP_CODE}" == "200" ]] && ok "${svc} /health → ${HTTP_CODE} (${TIME_MS}ms)" || fail "${svc} /health → ${HTTP_CODE} (expected 200)"
  [[ "${TIME_MS}" -gt 3000 ]] && warn "${svc} response ${TIME_MS}ms > 3000ms" || true
done

RENTALS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${GATEWAY_URL}/api/v1/rentals" 2>/dev/null || echo "000")
[[ "${RENTALS_CODE}" =~ ^(200|401)$ ]] && ok "GET /api/v1/rentals → ${RENTALS_CODE}" || fail "GET /api/v1/rentals → ${RENTALS_CODE} (expected 200 or 401)"

# ── 3. TLS Certificate ────────────────────────────────────────────────────────
echo ""
echo "▶ Section 3: TLS"

if command -v openssl &>/dev/null; then
  CERT_END=$(echo | timeout 5 openssl s_client -connect "${DOMAIN}:443" -servername "${DOMAIN}" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)
  if [[ -n "${CERT_END}" ]]; then
    EXPIRY_EPOCH=$(date -d "${CERT_END}" +%s 2>/dev/null || echo 0)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - $(date +%s)) / 86400 ))
    if [[ "${DAYS_LEFT}" -gt 14 ]]; then
      ok "TLS cert valid for ${DAYS_LEFT} more days"
    elif [[ "${DAYS_LEFT}" -gt 0 ]]; then
      warn "TLS cert expires in ${DAYS_LEFT} days"
    else
      fail "TLS cert EXPIRED"
    fi
  else
    warn "Cannot reach ${DOMAIN}:443 — skipping TLS (may be internal cluster)"
  fi
else
  warn "openssl not installed — skipping TLS check"
fi

# ── 4. Resource Thresholds ────────────────────────────────────────────────────
echo ""
echo "▶ Section 4: Resource Thresholds"

if kubectl top pods -n "${NAMESPACE}" &>/dev/null; then
  while IFS= read -r line; do
    pod=$(awk '{print $1}' <<< "$line")
    mem_raw=$(awk '{print $3}' <<< "$line")
    mem_mi=$(grep -oP '^\d+' <<< "${mem_raw}" || echo "0")
    unit=$(grep -oP '[A-Za-z]+$' <<< "${mem_raw}" || echo "Mi")
    [[ "${unit}" == "Gi" ]] && mem_mi=$((mem_mi * 1024)) || true
    [[ "${mem_mi}" -gt 450 ]] && warn "Pod '${pod}' memory ${mem_raw} > 450Mi" || true
  done < <(kubectl top pods -n "${NAMESPACE}" --no-headers 2>/dev/null | tail -n +2 || true)
  ok "Memory threshold check complete"
else
  warn "kubectl top unavailable — skipping resource check"
fi

# ── 5. Istio Health ───────────────────────────────────────────────────────────
echo ""
echo "▶ Section 5: Istio"

if kubectl get namespace istio-system &>/dev/null 2>&1; then
  NO_SIDECAR=$(kubectl get pods -n "${NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].name}{"\n"}{end}' \
    2>/dev/null | grep -vc "istio-proxy" || true)
  [[ "${NO_SIDECAR}" -eq 0 ]] && ok "All pods have istio-proxy sidecar" || warn "${NO_SIDECAR} pod(s) missing istio-proxy sidecar"
else
  info "Istio not installed — skipping"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e " Results: ${GREEN}${PASSED} passed${NC}  ${RED}${FAILED} failed${NC}  ${YELLOW}${WARNINGS} warnings${NC}"
echo "═══════════════════════════════════════════════════════════════"

if [[ "${NOTIFY}" == "discord" && -n "${DISCORD_WEBHOOK}" ]]; then
  COLOR=$([[ "${FAILED}" -eq 0 ]] && echo "3066993" || echo "15158332")
  EMOJI=$([[ "${FAILED}" -eq 0 ]] && echo "✅" || echo "❌")
  STATUS=$([[ "${FAILED}" -eq 0 ]] && echo "PASSED" || echo "FAILED")
  curl -s -X POST "${DISCORD_WEBHOOK}" \
    -H "Content-Type: application/json" \
    -d "{\"embeds\":[{\"title\":\"${EMOJI} Validation ${STATUS}\",\"description\":\"Cloud: ${CLOUD} | Env: ${ENV}\",\"color\":${COLOR},\"fields\":[{\"name\":\"Passed\",\"value\":\"${PASSED}\",\"inline\":true},{\"name\":\"Failed\",\"value\":\"${FAILED}\",\"inline\":true},{\"name\":\"Warnings\",\"value\":\"${WARNINGS}\",\"inline\":true}]}]}" \
    > /dev/null
fi

[[ "${FAILED}" -gt 0 ]] && exit 1 || exit 0
