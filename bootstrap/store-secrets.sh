#!/usr/bin/env bash
# =============================================================================
# store-secrets.sh — Store secrets in the platform Key Vault (run once per app)
#
# The platform Key Vault is shared across all your apps. Secrets are
# prefixed with "rentalapp-" for this project to avoid name collisions.
#
# Usage:
#   bash bootstrap/store-secrets.sh
#
# Prerequisites:
#   az login
#   PLATFORM_KV_NAME set in bootstrap/.env (Key Vault must already exist)
#
# Secrets stored:
#   github-pat                 → GitHub PAT shared by all your apps
#   argocd-github-pat          → GitHub PAT for ArgoCD (shared)
#   rentalapp-discord-webhook  → Discord webhook for this app only (prefixed)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}✔${RESET}  $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
error()   { echo -e "${RED}✘${RESET}  $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# ── Load identifiers from .env ────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  error ".env not found. Copy .env.example → .env and fill in config values."
  exit 1
fi

while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" != *"="* ]] && continue
  key="${line%%=*}"; key="${key// /}"
  val="${line#*=}"; val="${val#\"}"; val="${val%\"}"
  [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && export "$key=$val"
done < "$ENV_FILE"

# ── Verify Azure login ────────────────────────────────────────────────────────
info "Checking Azure login..."
az account show --output none 2>/dev/null || {
  error "Not logged in. Run: az login"
  exit 1
}
success "Azure session active"

# ── Resolve platform Key Vault ────────────────────────────────────────────────
KV="${PLATFORM_KV_NAME:-}"

if [[ -z "$KV" || "$KV" == *"<"* ]]; then
  PLATFORM_RG_VAL="${PLATFORM_RG:-}"
  if [[ -n "$PLATFORM_RG_VAL" && "$PLATFORM_RG_VAL" != *"<"* ]]; then
    info "PLATFORM_KV_NAME not set — discovering from: $PLATFORM_RG_VAL"
    KV=$(az keyvault list \
      --resource-group "$PLATFORM_RG_VAL" \
      --query "[0].name" -o tsv 2>/dev/null || echo "")
  fi
fi

if [[ -z "$KV" ]]; then
  error "Platform Key Vault not found."
  echo  "  Set PLATFORM_KV_NAME in bootstrap/.env and re-run."
  exit 1
fi
success "Platform Key Vault: $KV"

echo ""
echo -e "${BOLD}${CYAN}━━━ Store secrets in Key Vault: $KV ━━━${RESET}"
echo "  Input is hidden. Press Enter to keep the existing value."
echo ""

# ── Helper: prompt and store ──────────────────────────────────────────────────
store_secret() {
  local kv_secret_name="$1"
  local display_label="$2"
  local hint="$3"
  local shared="${4:-false}"   # "true" = shared across apps, "false" = app-scoped

  echo -e "  ${BOLD}$kv_secret_name${RESET}"
  [[ "$shared" == "true" ]] && echo "    (shared across all your apps)"
  echo "    $hint"

  local existing
  existing=$(az keyvault secret show \
    --vault-name "$KV" \
    --name "$kv_secret_name" \
    --query value -o tsv 2>/dev/null || echo "")

  if [[ -n "$existing" ]]; then
    warn "  Already set. Press Enter to keep, or type a new value to replace:"
  fi

  local value
  read -rs -p "  $display_label: " value
  echo ""

  if [[ -z "$value" && -n "$existing" ]]; then
    success "  Kept existing: $kv_secret_name"
    echo ""
    return 0
  fi

  if [[ -z "$value" ]]; then
    warn "  Skipped (no value entered): $kv_secret_name"
    echo ""
    return 0
  fi

  az keyvault secret set \
    --vault-name "$KV" \
    --name "$kv_secret_name" \
    --value "$value" \
    --output none
  success "  Stored: $kv_secret_name"
  echo ""
}

# ── Shared secrets (same value across all your apps) ─────────────────────────
store_secret \
  "github-pat" \
  "GitHub PAT" \
  "Classic PAT with 'repo' scope → https://github.com/settings/tokens/new" \
  "true"

store_secret \
  "argocd-github-pat" \
  "ArgoCD GitHub PAT" \
  "Classic PAT with 'repo' scope for ArgoCD private repo access" \
  "true"

# ── App-scoped secrets (prefixed with app name) ───────────────────────────────
store_secret \
  "rentalapp-discord-webhook" \
  "Discord Webhook URL (rentalapp)" \
  "Discord → Server Settings → Integrations → Webhooks → Copy URL" \
  "false"

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}${GREEN}━━━ Done ━━━${RESET}"
echo ""
echo "  Secrets stored in platform Key Vault: $KV"
echo ""
echo "  Next steps:"
echo "    Load into shell:        source bootstrap/load-secrets.sh"
echo "    Push to GitHub Secrets: python bootstrap/set-github-secrets.py"
echo ""
