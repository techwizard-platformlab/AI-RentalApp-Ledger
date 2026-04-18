#!/usr/bin/env bash
# =============================================================================
# load-secrets.sh — Load secrets from the platform Key Vault into this shell
#
# Usage (must be sourced, not executed):
#   source bootstrap/load-secrets.sh
#
# Prerequisites:
#   az login                     ← active Azure session
#   PLATFORM_KV_NAME set in .env ← Key Vault must already exist
#
# What it does:
#   1. Loads identifiers from bootstrap/.env
#   2. Resolves the platform Key Vault (PLATFORM_KV_NAME or auto-discovers)
#   3. Exports GITHUB_PAT, ARGOCD_GITHUB_PAT, DISCORD_WEBHOOK_URL into shell
#      (memory only — never written to disk)
# =============================================================================

# Guard: must be sourced not executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: This script must be sourced, not executed."
  echo "  Usage: source bootstrap/load-secrets.sh"
  exit 1
fi

_ls_green='\033[0;32m'; _ls_yellow='\033[1;33m'
_ls_red='\033[0;31m'; _ls_reset='\033[0m'
_ls_ok()   { echo -e "${_ls_green}✔${_ls_reset}  $*"; }
_ls_warn() { echo -e "${_ls_yellow}⚠${_ls_reset}  $*"; }
_ls_err()  { echo -e "${_ls_red}✘${_ls_reset}  $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# ── Step 1: Load identifiers from .env ───────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  _ls_err ".env not found at: $ENV_FILE"
  _ls_warn "Copy .env.example → .env and fill in your values."
  return 1
fi

while IFS= read -r _line; do
  [[ -z "$_line" || "$_line" =~ ^[[:space:]]*# ]] && continue
  [[ "$_line" != *"="* ]] && continue
  _key="${_line%%=*}"; _key="${_key// /}"
  _val="${_line#*=}"; _val="${_val#\"}"; _val="${_val%\"}"
  [[ "$_key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && export "$_key=$_val"
done < "$ENV_FILE"
_ls_ok "Config loaded from .env"

# ── Step 2: Resolve platform Key Vault ───────────────────────────────────────
_KV="${PLATFORM_KV_NAME:-}"

if [[ -z "$_KV" || "$_KV" == *"<"* ]]; then
  # Fall back: auto-discover from PLATFORM_RG
  _PLATFORM_RG="${PLATFORM_RG:-}"
  if [[ -n "$_PLATFORM_RG" && "$_PLATFORM_RG" != *"<"* ]]; then
    _ls_warn "PLATFORM_KV_NAME not set — discovering from resource group: $_PLATFORM_RG"
    _KV=$(az keyvault list \
      --resource-group "$_PLATFORM_RG" \
      --query "[0].name" -o tsv 2>/dev/null || echo "")
  fi
fi

if [[ -z "$_KV" ]]; then
  _ls_err "Platform Key Vault not found."
  echo "  Fix: set PLATFORM_KV_NAME in bootstrap/.env"
  echo "  e.g. PLATFORM_KV_NAME=\"kv-platform-abc123\""
  return 1
fi
_ls_ok "Key Vault: $_KV"

# ── Step 3: Fetch secrets into shell memory ───────────────────────────────────
_kv_get() {
  az keyvault secret show \
    --vault-name "$_KV" \
    --name "$1" \
    --query value -o tsv 2>/dev/null || echo ""
}

export GITHUB_PAT;          GITHUB_PAT=$(_kv_get "github-pat")
export ARGOCD_GITHUB_PAT;   ARGOCD_GITHUB_PAT=$(_kv_get "argocd-github-pat")
export DISCORD_WEBHOOK_URL; DISCORD_WEBHOOK_URL=$(_kv_get "rentalapp-discord-webhook")

# ── Step 4: Report ────────────────────────────────────────────────────────────
[[ -n "$GITHUB_PAT" ]]          && _ls_ok  "GITHUB_PAT loaded" \
                                 || _ls_warn "GITHUB_PAT not in Key Vault (run: bash bootstrap/store-secrets.sh)"
[[ -n "$ARGOCD_GITHUB_PAT" ]]   && _ls_ok  "ARGOCD_GITHUB_PAT loaded" \
                                 || _ls_warn "ARGOCD_GITHUB_PAT not in Key Vault"
[[ -n "$DISCORD_WEBHOOK_URL" ]] && _ls_ok  "DISCORD_WEBHOOK_URL loaded" \
                                 || _ls_warn "DISCORD_WEBHOOK_URL not in Key Vault"

echo ""
echo "  Secrets are in memory only — cleared when this terminal closes."
echo "  Re-run 'source bootstrap/load-secrets.sh' in each new session."

unset _line _key _val _KV _PLATFORM_RG
unset -f _ls_ok _ls_warn _ls_err _kv_get
