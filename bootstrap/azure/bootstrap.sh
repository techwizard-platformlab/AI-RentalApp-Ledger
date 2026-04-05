#!/usr/bin/env bash
# =============================================================================
# rentalAppLedger — Azure Bootstrap (KodeKloud-aware, standalone)
#
# Run this directly only if you want to bootstrap Azure in isolation.
# Normally called from: bootstrap/bootstrap.sh (CLOUD=azure or CLOUD=both)
#
# KodeKloud hard constraints respected:
#   - Does NOT attempt role assignment (pre-granted by KodeKloud internally)
#   - Does NOT create a new resource group (uses the pre-existing one)
#   - Does NOT attempt non-interactive login (az login required beforehand)
#   - Uses the pre-existing SP (APP_ID) for GitHub Actions auth
#
# Auth approach:
#   PRIMARY  — OIDC federated credentials on pre-existing SP (best-effort add)
#   FALLBACK — Client secret on pre-existing SP (set AZURE_CLIENT_SECRET)
#
# Usage (standalone):
#   az login                        # once in browser
#   bash bootstrap/azure/bootstrap.sh
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}✔${RESET}  $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
error()   { echo -e "${RED}✘${RESET}  $*" >&2; }
blank()   { echo ""; }

# =============================================================================
# When invoked standalone this script loads its own .env.
# When called from the parent bootstrap.sh the variables are already exported.
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/bootstrap"
ENV_FILE="$BOOTSTRAP_ROOT/.env"

# Load .env only if variables are not already in the environment
if [[ -z "${AZURE_SUBSCRIPTION_ID:-}" && -f "$ENV_FILE" ]]; then
  # Minimal safe loader: handles quotes, inline comments, trailing whitespace
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *"="* ]] && continue
    local_key="${line%%=*}"
    local_val="${line#*=}"
    local_key="${local_key#"${local_key%%[![:space:]]*}"}"
    local_key="${local_key%"${local_key##*[![:space:]]}"}"
    [[ -z "$local_key" || ! "$local_key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && continue
    if [[ "$local_val" =~ ^[[:space:]]*\"([^\"]*)\" ]]; then
      local_val="${BASH_REMATCH[1]}"
    elif [[ "$local_val" =~ ^[[:space:]]*\'([^\']*)\' ]]; then
      local_val="${BASH_REMATCH[1]}"
    else
      local_val="${local_val%%[[:space:]]#*}"
      local_val="${local_val%"${local_val##*[![:space:]]}"}"
    fi
    export "$local_key=$local_val"
  done < "$ENV_FILE"
fi

# ── Resolve configuration values ──────────────────────────────────────────────
RG="${AZURE_RG:-}"
LOCATION="${AZURE_LOCATION:-eastus}"
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
TENANT_ID="${AZURE_TENANT_ID:-}"
APP_ID="${AZURE_APP_ID:-8f4772d5-9056-4f3a-98e6-d0fb30d9592b}"
GITHUB_ORG="${GITHUB_ORG:-}"
GITHUB_REPO="${GITHUB_REPO:-AI-RentalApp-Ledger}"
CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"
CONTAINER_NAME="tfstate"

# ── Validate required variables ───────────────────────────────────────────────
failed=0
for var in SUBSCRIPTION_ID TENANT_ID RG GITHUB_ORG; do
  val="${!var:-}"
  if [[ -z "$val" || "$val" == *"<"* ]]; then
    error "Missing or unfilled: ${BOLD}${var}${RESET} — set it in bootstrap/.env"
    failed=1
  fi
done
[[ "$failed" -eq 0 ]] || { blank; echo "  Fix the above in bootstrap/.env and re-run."; exit 1; }

# =============================================================================
# STEP 1 — Verify az login session
# =============================================================================
info "Checking Azure login session..."

if ! az account show --output none 2>/dev/null; then
  blank
  error "No active Azure login session found."
  echo  "  ┌─────────────────────────────────────────────────────────────┐"
  echo  "  │  Run this in your terminal, then re-run bootstrap:          │"
  echo  "  │                                                             │"
  echo  "  │    az login                                                 │"
  echo  "  │                                                             │"
  echo  "  │  A browser window will open. Sign in with:                 │"
  echo  "  │    $AZURE_LAB_USERNAME"
  echo  "  │                                                             │"
  echo  "  │  After login completes, re-run:                            │"
  echo  "  │    bash bootstrap/bootstrap.sh                              │"
  echo  "  └─────────────────────────────────────────────────────────────┘"
  exit 1
fi

ACTIVE_ACCOUNT=$(az account show --query user.name -o tsv 2>/dev/null || true)
success "Logged in as: ${ACTIVE_ACCOUNT:-<unknown>}"

# =============================================================================
# STEP 2 — Set and verify subscription
# =============================================================================
info "Setting subscription: $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"

CONFIRMED_SUB=$(az account show --query id -o tsv)
if [[ "$CONFIRMED_SUB" != "$SUBSCRIPTION_ID" ]]; then
  error "Subscription mismatch: expected '$SUBSCRIPTION_ID', got '$CONFIRMED_SUB'"
  exit 1
fi
success "Active subscription confirmed: $SUBSCRIPTION_ID"

# Resolve tenant ID from the current session (handles domain vs GUID)
SESSION_TENANT=$(az account show --query tenantId -o tsv 2>/dev/null || true)
if [[ -n "$SESSION_TENANT" ]]; then
  TENANT_ID="$SESSION_TENANT"
fi

# =============================================================================
# STEP 3 — Create Terraform state Storage Account (idempotent)
# =============================================================================
info "Checking for existing Terraform state storage account in RG: $RG"

SA_NAME=$(az storage account list \
  --resource-group "$RG" \
  --query "[?starts_with(name,'rentalledgertf')].name" \
  -o tsv 2>/dev/null | head -1 || true)

if [[ -n "$SA_NAME" ]]; then
  success "Storage account already exists: $SA_NAME (skipping create)"
else
  # Generate a short random suffix — safe cross-platform (no /proc dependency)
  SA_SUFFIX=$(openssl rand -hex 4 2>/dev/null || date +%s | tail -c 8)
  SA_NAME="rentalledgertf${SA_SUFFIX}"

  info "Creating Storage Account: $SA_NAME"
  az storage account create \
    --name                    "$SA_NAME" \
    --resource-group          "$RG" \
    --location                "$LOCATION" \
    --sku                     Standard_LRS \
    --kind                    StorageV2 \
    --https-only              true \
    --allow-blob-public-access false \
    --min-tls-version         TLS1_2 \
    --output none
  success "Storage account created: $SA_NAME"
fi

# =============================================================================
# STEP 4 — Create blob container (idempotent)
# =============================================================================
info "Ensuring blob container exists: $CONTAINER_NAME"

# Try with --auth-mode login first; fall back to key-based if RBAC not ready
if az storage container create \
    --name         "$CONTAINER_NAME" \
    --account-name "$SA_NAME" \
    --auth-mode    login \
    --output none 2>/dev/null; then
  success "Blob container ready (auth: login): $CONTAINER_NAME"
else
  az storage container create \
    --name         "$CONTAINER_NAME" \
    --account-name "$SA_NAME" \
    --output none
  success "Blob container ready (auth: key): $CONTAINER_NAME"
fi

# =============================================================================
# STEP 5 — Best-effort: add OIDC federated credentials to existing SP
#
# KodeKloud may or may not allow federated-credential creation on the SP.
# We try both the main-branch and pull-request subjects; skip gracefully if
# the operation is denied (role/permission constraint).
#
# NOTE: Role assignment is intentionally skipped entirely.
#       KodeKloud internally pre-grants the SP Contributor access to the RG.
# =============================================================================
info "Attempting to add OIDC federated credentials to SP: $APP_ID (best-effort)"
blank
warn "Role assignments are SKIPPED — KodeKloud pre-grants SP access to the RG."
warn "Do NOT attempt az role assignment create — it will be rejected."
blank

add_federated_credential() {
  local fc_name="$1"
  local subject="$2"

  # Check whether it already exists
  local existing
  existing=$(az ad app federated-credential list \
    --id "$APP_ID" \
    --query "[?name=='${fc_name}'].name" \
    -o tsv 2>/dev/null || true)

  if [[ -n "$existing" ]]; then
    success "Federated credential already exists: $fc_name (skipping)"
    return 0
  fi

  # Attempt to create — capture stderr to detect permission denials
  local err_output
  if err_output=$(az ad app federated-credential create \
      --id "$APP_ID" \
      --parameters "{
        \"name\": \"${fc_name}\",
        \"issuer\": \"https://token.actions.githubusercontent.com\",
        \"subject\": \"${subject}\",
        \"audiences\": [\"api://AzureADTokenExchange\"]
      }" 2>&1); then
    success "Federated credential added: $fc_name"
  else
    warn "Could not add federated credential '$fc_name' — OIDC may be restricted."
    warn "Error: $err_output"
    warn "Use the client-secret fallback instead (see GitHub secrets output below)."
  fi
}

add_federated_credential \
  "github-main" \
  "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"

add_federated_credential \
  "github-pr" \
  "repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request"

# =============================================================================
# STEP 6 — Print GitHub Secrets
#
# Both OIDC and client-secret options are printed so you can choose whichever
# works in your KodeKloud session.
# =============================================================================
blank
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║  AZURE — GitHub → Settings → Secrets → Actions                      ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
blank

# ── Option A: OIDC (preferred — no expiring secret) ──────────────────────────
echo -e "  ${BOLD}${CYAN}Option A — OIDC / Federated Credentials (preferred, no expiry)${RESET}"
echo -e "  Use this if the federated credentials above were added successfully."
echo -e "  GitHub Actions workflow needs: permissions: id-token: write"
blank
echo -e "  ${BOLD}AZURE_CLIENT_ID${RESET}        = $APP_ID"
echo -e "  ${BOLD}AZURE_TENANT_ID${RESET}        = $TENANT_ID"
echo -e "  ${BOLD}AZURE_SUBSCRIPTION_ID${RESET}  = $SUBSCRIPTION_ID"
echo -e "  ${BOLD}TF_BACKEND_RG${RESET}          = $RG"
echo -e "  ${BOLD}TF_BACKEND_SA${RESET}          = $SA_NAME"
echo -e "  ${BOLD}TF_BACKEND_CONTAINER${RESET}   = $CONTAINER_NAME"
blank

# ── Option B: Client Secret fallback ─────────────────────────────────────────
echo -e "  ${BOLD}${YELLOW}Option B — Client Secret fallback (expires each KodeKloud session)${RESET}"
echo -e "  Use this if OIDC did not work or federated credential creation was denied."
blank
echo -e "  ${BOLD}AZURE_CLIENT_ID${RESET}        = $APP_ID"
echo -e "  ${BOLD}AZURE_TENANT_ID${RESET}        = $TENANT_ID"
echo -e "  ${BOLD}AZURE_SUBSCRIPTION_ID${RESET}  = $SUBSCRIPTION_ID"

if [[ -n "$CLIENT_SECRET" ]]; then
  echo -e "  ${BOLD}AZURE_CLIENT_SECRET${RESET}    = $CLIENT_SECRET"
else
  echo -e "  ${BOLD}AZURE_CLIENT_SECRET${RESET}    = <not set — generate in Azure Portal>"
  echo -e "                          Azure Portal → App Registrations"
  echo -e "                          → App: $APP_ID"
  echo -e "                          → Certificates & secrets → New client secret"
  echo -e "                          → Copy the Value immediately after creation"
  echo -e "                          → Set AZURE_CLIENT_SECRET in bootstrap/.env"
  echo -e "                          → Re-run bootstrap.sh to see it printed here"
fi

echo -e "  ${BOLD}TF_BACKEND_RG${RESET}          = $RG"
echo -e "  ${BOLD}TF_BACKEND_SA${RESET}          = $SA_NAME"
echo -e "  ${BOLD}TF_BACKEND_CONTAINER${RESET}   = $CONTAINER_NAME"
blank

# ── Terraform backend block ───────────────────────────────────────────────────
echo -e "  ${BOLD}terraform/azure/backend.tf:${RESET}"
printf   '    resource_group_name  = "%s"\n' "$RG"
printf   '    storage_account_name = "%s"\n' "$SA_NAME"
printf   '    container_name       = "%s"\n' "$CONTAINER_NAME"
printf   '    key                  = "dev.terraform.tfstate"\n'
blank

# ── KodeKloud reminders ───────────────────────────────────────────────────────
echo -e "  ${BOLD}${YELLOW}KodeKloud reminders:${RESET}"
echo    "  - Role assignments are pre-granted by KodeKloud. Do NOT try to assign"
echo    "    roles manually — the operation will be rejected."
echo    "  - Client secrets expire at the end of each lab session."
echo    "    Regenerate AZURE_CLIENT_SECRET and update GitHub secrets each time."
echo    "  - OIDC federated credentials do not expire — prefer Option A if it works."
blank

success "Azure bootstrap complete."
