#!/usr/bin/env bash
# =============================================================================
# rentalAppLedger — Azure Bootstrap
#
# Creates the permanent shared infrastructure in my-Rental-App:
#   - Terraform state storage account + container
#   - Env resource groups (my-Rental-App-Dev, my-Rental-App-QA)
#   - Federated credentials on the managed identity
#   - Role assignments for the managed identity
#
# Run ONCE per subscription. Idempotent — safe to re-run.
#
# Prerequisites:
#   az login
#   Managed identity already created in my-Rental-App (via Azure Portal or az CLI)
#
# Usage:
#   bash bootstrap/azure/bootstrap.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}✔${RESET}  $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
error()   { echo -e "${RED}✘${RESET}  $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/bootstrap"
ENV_FILE="$BOOTSTRAP_ROOT/.env"

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *"="* ]] && continue
    key="${line%%=*}"; val="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
    [[ -z "$key" || ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && continue
    val="${val%%[[:space:]]#*}"; val="${val%"${val##*[![:space:]]}"}"
    [[ "$val" =~ ^\"(.*)\"$ ]] && val="${BASH_REMATCH[1]}"
    [[ "$val" =~ ^\'(.*)\'$ ]] && val="${BASH_REMATCH[1]}"
    export "$key=$val"
  done < "$ENV_FILE"
fi

# ── Config ─────────────────────────────────────────────────────────────────────
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
SHARED_RG="${AZURE_SHARED_RG:-my-Rental-App}"
LOCATION="${AZURE_LOCATION:-eastus}"
IDENTITY_NAME="${AZURE_IDENTITY_NAME:-}"
GITHUB_ORG="${GITHUB_ORG:-techwizard-platformlab}"
GITHUB_REPO="${GITHUB_REPO:-AI-RentalApp-Ledger}"
BUILD_REPO="${BUILD_REPO:-RentalApp-Build}"
CONTAINER_NAME="tfstate"

# Env resource groups (created here, populated by Terraform)
DEV_RG="my-Rental-App-Dev"
QA_RG="my-Rental-App-QA"

# ── Validate ───────────────────────────────────────────────────────────────────
failed=0
for var in SUBSCRIPTION_ID IDENTITY_NAME GITHUB_ORG; do
  if [[ -z "${!var:-}" || "${!var}" == *"<"* ]]; then
    error "Missing: ${BOLD}${var}${RESET} — set it in bootstrap/.env"
    failed=1
  fi
done
[[ "$failed" -eq 0 ]] || exit 1

# ── Verify login ───────────────────────────────────────────────────────────────
info "Checking Azure login..."
az account show --output none 2>/dev/null || {
  error "Not logged in. Run: az login"
  exit 1
}
az account set --subscription "$SUBSCRIPTION_ID"
TENANT_ID=$(az account show --query tenantId -o tsv)
IDENTITY_CLIENT_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$SHARED_RG" --query clientId -o tsv 2>/dev/null || true)
IDENTITY_PRINCIPAL_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$SHARED_RG" --query principalId -o tsv 2>/dev/null || true)

if [[ -z "$IDENTITY_CLIENT_ID" ]]; then
  error "Managed identity '$IDENTITY_NAME' not found in '$SHARED_RG'."
  error "Create it first: az identity create --name $IDENTITY_NAME --resource-group $SHARED_RG --location $LOCATION"
  exit 1
fi
success "Identity found: $IDENTITY_NAME (clientId: $IDENTITY_CLIENT_ID)"

# =============================================================================
# STEP 1 — Create Terraform state storage account
# =============================================================================
info "Setting up Terraform state storage in: $SHARED_RG"

SA_NAME=$(az storage account list \
  --resource-group "$SHARED_RG" \
  --query "[?starts_with(name,'rentalledgertf')].name" \
  -o tsv 2>/dev/null | head -1 || true)

if [[ -n "$SA_NAME" ]]; then
  success "State storage account already exists: $SA_NAME"
else
  SA_SUFFIX=$(openssl rand -hex 4)
  SA_NAME="rentalledgertf${SA_SUFFIX}"
  info "Creating storage account: $SA_NAME"
  az storage account create \
    --name "$SA_NAME" \
    --resource-group "$SHARED_RG" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --https-only true \
    --allow-blob-public-access false \
    --min-tls-version TLS1_2 \
    --output none
  success "Created: $SA_NAME"
fi

# Container
if az storage container create --name "$CONTAINER_NAME" --account-name "$SA_NAME" --auth-mode login --output none 2>/dev/null; then
  success "Blob container ready: $CONTAINER_NAME"
else
  az storage container create --name "$CONTAINER_NAME" --account-name "$SA_NAME" --output none 2>/dev/null || true
  success "Blob container ready (key auth): $CONTAINER_NAME"
fi

# =============================================================================
# STEP 2 — Create env resource groups
# =============================================================================
for ENV_RG in "$DEV_RG" "$QA_RG"; do
  info "Ensuring resource group exists: $ENV_RG"
  if az group show --name "$ENV_RG" --output none 2>/dev/null; then
    success "Already exists: $ENV_RG"
  else
    az group create --name "$ENV_RG" --location "$LOCATION" --output none
    success "Created: $ENV_RG"
  fi
done

# =============================================================================
# STEP 3 — Role assignments for managed identity
# =============================================================================
info "Assigning roles to managed identity: $IDENTITY_NAME"

assign_role() {
  local role="$1"
  local scope="$2"
  local label="$3"

  if az role assignment list --assignee "$IDENTITY_PRINCIPAL_ID" --role "$role" --scope "$scope" --query "[0].id" -o tsv 2>/dev/null | grep -q .; then
    success "Role already assigned: $role on $label"
  else
    az role assignment create \
      --assignee "$IDENTITY_PRINCIPAL_ID" \
      --role "$role" \
      --scope "$scope" \
      --output none 2>/dev/null && success "Assigned: $role on $label" || warn "Could not assign $role on $label — check permissions"
  fi
}

SUB_SCOPE="/subscriptions/$SUBSCRIPTION_ID"
DEV_SCOPE=$(az group show --name "$DEV_RG" --query id -o tsv)
QA_SCOPE=$(az group show --name "$QA_RG" --query id -o tsv)
SA_SCOPE=$(az storage account show --name "$SA_NAME" --resource-group "$SHARED_RG" --query id -o tsv)

assign_role "Contributor"                    "$DEV_SCOPE" "$DEV_RG"
assign_role "Contributor"                    "$QA_SCOPE"  "$QA_RG"
assign_role "Contributor"                    "$SUB_SCOPE/resourceGroups/$SHARED_RG" "$SHARED_RG (for ACR/KV creation)"
assign_role "Storage Blob Data Contributor"  "$SA_SCOPE"  "state storage account"
assign_role "Key Vault Secrets Officer"      "$SUB_SCOPE/resourceGroups/$SHARED_RG" "shared RG (Key Vault secrets)"
assign_role "AcrPush"                        "$SUB_SCOPE/resourceGroups/$SHARED_RG" "shared RG (ACR push)"

# =============================================================================
# STEP 4 — Federated credentials
# =============================================================================
info "Setting up federated credentials..."

add_federated_credential() {
  local name="$1" subject="$2"
  local existing
  existing=$(az identity federated-credential list --identity-name "$IDENTITY_NAME" --resource-group "$SHARED_RG" \
    --query "[?name=='${name}'].name" -o tsv 2>/dev/null || true)
  if [[ -n "$existing" ]]; then
    success "Federated credential exists: $name"
    return 0
  fi
  local err
  if err=$(az identity federated-credential create \
      --name "$name" \
      --identity-name "$IDENTITY_NAME" \
      --resource-group "$SHARED_RG" \
      --issuer "https://token.actions.githubusercontent.com" \
      --subject "$subject" \
      --audiences '["api://AzureADTokenExchange"]' 2>&1); then
    success "Created federated credential: $name"
  else
    warn "Could not create: $name — $err"
  fi
}

# Platform repo (AI-RentalApp-Ledger)
add_federated_credential "github-platform-dev"         "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:dev"
add_federated_credential "github-platform-destructive" "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:terraform-destructive-approval"
add_federated_credential "github-platform-shared"      "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:shared"

# Build repo (RentalApp-Build)
add_federated_credential "github-build-main"           "repo:${GITHUB_ORG}/${BUILD_REPO}:ref:refs/heads/main"
add_federated_credential "github-build-dispatch"       "repo:${GITHUB_ORG}/${BUILD_REPO}:workflow_dispatch"

# =============================================================================
# STEP 5 — Print GitHub Secrets
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║  GitHub Secrets — both repos                                        ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}── techwizard-platformlab/AI-RentalApp-Ledger ──────────────────────${RESET}"
echo -e "  ${BOLD}AZURE_CLIENT_ID${RESET}            = $IDENTITY_CLIENT_ID"
echo -e "  ${BOLD}AZURE_TENANT_ID${RESET}            = $TENANT_ID"
echo -e "  ${BOLD}AZURE_SUBSCRIPTION_ID${RESET}      = $SUBSCRIPTION_ID"
echo -e "  ${BOLD}TF_BACKEND_RG${RESET}              = $SHARED_RG"
echo -e "  ${BOLD}TF_BACKEND_SA${RESET}              = $SA_NAME"
echo -e "  ${BOLD}TF_BACKEND_CONTAINER${RESET}       = $CONTAINER_NAME"
echo -e "  ${BOLD}TF_SHARED_RG${RESET}               = $SHARED_RG"
echo -e "  ${BOLD}ACR_NAME${RESET}                   = <from: terraform -chdir=infrastructure/azure/shared output acr_name>"
echo -e "  ${BOLD}KEY_VAULT_NAME${RESET}             = <from: terraform -chdir=infrastructure/azure/shared output key_vault_name>"
echo ""
echo -e "  ${BOLD}── techwizard-platformlab/RentalApp-Build ──────────────────────────${RESET}"
echo -e "  ${BOLD}AZURE_CLIENT_ID${RESET}            = $IDENTITY_CLIENT_ID"
echo -e "  ${BOLD}AZURE_TENANT_ID${RESET}            = $TENANT_ID"
echo -e "  ${BOLD}AZURE_SUBSCRIPTION_ID${RESET}      = $SUBSCRIPTION_ID"
echo -e "  ${BOLD}ACR_NAME${RESET}                   = <from: terraform -chdir=infrastructure/azure/shared output acr_name>"
echo -e "  ${BOLD}ACR_LOGIN_SERVER${RESET}           = <from: terraform -chdir=infrastructure/azure/shared output acr_login_server>"
echo ""
echo -e "  ${BOLD}── After running shared Terraform ──────────────────────────────────${RESET}"
echo -e "  Run these to get ACR and Key Vault names:"
echo -e "  ${CYAN}  cd infrastructure/azure/shared${RESET}"
echo -e "  ${CYAN}  terraform init -backend-config=\"resource_group_name=$SHARED_RG\" \\${RESET}"
echo -e "  ${CYAN}    -backend-config=\"storage_account_name=$SA_NAME\" \\${RESET}"
echo -e "  ${CYAN}    -backend-config=\"container_name=$CONTAINER_NAME\"${RESET}"
echo -e "  ${CYAN}  terraform apply -var=\"subscription_id=\$AZURE_SUBSCRIPTION_ID\" \\${RESET}"
echo -e "  ${CYAN}    -var=\"shared_resource_group_name=$SHARED_RG\"${RESET}"
echo -e "  ${CYAN}  terraform output acr_name${RESET}"
echo -e "  ${CYAN}  terraform output key_vault_name${RESET}"
echo ""
success "Bootstrap complete."
