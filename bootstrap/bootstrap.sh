#!/usr/bin/env bash
# =============================================================================
# rentalAppLedger — Unified Bootstrap Script
#
# Azure auth strategy: User-Assigned Managed Identity + OIDC federated creds.
# No Service Principal, no client secrets, no role assignment restrictions.
#
# What this script does (Azure):
#   1. Verifies az login + ARM token
#   2. Creates Terraform state Storage Account in the shared RG (idempotent)
#   3. Adds OIDC federated credentials to the Managed Identity
#   4. Prints GitHub Actions secrets to copy
#
# GCP: Workload Identity Pool for GitHub Actions OIDC (unchanged)
#
# Setup:
#   cp bootstrap/.env.example bootstrap/.env
#   # Fill in bootstrap/.env
#   az login                         # browser-based, once per session
#   bash bootstrap/bootstrap.sh
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}✔${RESET}  $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
error()   { echo -e "${RED}✘${RESET}  $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${RESET}"; }
blank()   { echo ""; }

# ── Load .env ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  error ".env not found at: $ENV_FILE"
  blank
  echo "  Create it first:"
  echo "    cp bootstrap/.env.example bootstrap/.env"
  echo "  Then fill in your values and re-run."
  exit 1
fi

# Safe .env loader — handles special chars, inline comments, surrounding quotes
load_env() {
  local file="$1"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *"="* ]] && continue

    local key="${line%%=*}"
    local val="${line#*=}"

    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    [[ -z "$key" || ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && continue

    if [[ "$val" =~ ^[[:space:]]*\"([^\"]*)\" ]]; then
      val="${BASH_REMATCH[1]}"
    elif [[ "$val" =~ ^[[:space:]]*\'([^\']*)\' ]]; then
      val="${BASH_REMATCH[1]}"
    else
      val="${val%%[[:space:]]#*}"
      val="${val%"${val##*[![:space:]]}"}"
    fi

    export "$key=$val"
  done < "$file"
}

load_env "$ENV_FILE"
success "Loaded: $ENV_FILE"

# ── Debug: show loaded values ─────────────────────────────────────────────────
debug_env() {
  blank
  echo -e "${BOLD}  Values loaded from .env:${RESET}"
  echo    "  CLOUD                 = ${CLOUD:-<not set>}"
  echo    "  GITHUB_ORG            = ${GITHUB_ORG:-<not set>}"
  echo    "  GITHUB_REPO           = ${GITHUB_REPO:-<not set>}"
  echo    "  AZURE_IDENTITY_NAME   = ${AZURE_IDENTITY_NAME:-<not set>}"
  echo    "  AZURE_LOCATION        = ${AZURE_LOCATION:-<not set>}"
  blank
}

if [[ "${1:-}" == "--debug" || "${BOOTSTRAP_DEBUG:-0}" == "1" ]]; then
  debug_env
fi

# ── Validate a variable is set and not a placeholder ─────────────────────────
require() {
  local var="$1" label="${2:-$1}"
  local val="${!var:-}"
  if [[ -z "$val" || "$val" == *"<"* ]]; then
    error "Missing or unfilled in .env: ${BOLD}${label}${RESET}"
    return 1
  fi
}

# ── Cloud selection ───────────────────────────────────────────────────────────
select_cloud() {
  local cloud_val="${CLOUD:-}"
  cloud_val="${cloud_val#"${cloud_val%%[![:space:]]*}"}"
  cloud_val="${cloud_val%"${cloud_val##*[![:space:]]}"}"
  cloud_val="${cloud_val//\"/}"
  cloud_val="${cloud_val//\'/}"
  cloud_val="${cloud_val,,}"

  case "$cloud_val" in
    azure|az|1) CLOUD_CHOICE="azure" ;;
    gcp|gce|2)  CLOUD_CHOICE="gcp"   ;;
    both|all|3) CLOUD_CHOICE="both"  ;;
    *)
      error "Invalid CLOUD='${CLOUD:-}' in .env — use: azure | gcp | both"
      exit 1 ;;
  esac
  info "Cloud: ${BOLD}${CLOUD_CHOICE}${RESET}"
}

# =============================================================================
# AZURE BOOTSTRAP
#
# Uses a User-Assigned Managed Identity for GitHub Actions OIDC auth.
# The MI must already exist in the platform resource group (techwizard-platformlab-apps).
# This script adds federated credentials to it and sets up Terraform state.
# =============================================================================
bootstrap_azure() {
  header "AZURE BOOTSTRAP"

  # ── Validate required .env variables ───────────────────────────────────────
  local failed=0
  require AZURE_LOCATION  || failed=1
  require GITHUB_ORG      || failed=1
  require GITHUB_REPO     || failed=1
  local PLATFORM_RG_VAL="${PLATFORM_RG:-techwizard-platformlab-apps}"
  local IDENTITY_NAME="${PLATFORM_MI_NAME:-${AZURE_IDENTITY_NAME:-automation}}"
  [[ "$failed" -eq 0 ]] || { blank; echo "  Fix the above in bootstrap/.env and re-run."; exit 1; }

  local LOCATION="$AZURE_LOCATION"
  local CONTAINER_NAME="tfstate"

  # ── Resolve Azure identifiers from active session (not from .env) ───────────
  local SUBSCRIPTION_ID TENANT_ID CLIENT_ID
  SUBSCRIPTION_ID=$(az account show --query id        -o tsv 2>/dev/null || true)
  TENANT_ID=$(      az account show --query tenantId  -o tsv 2>/dev/null || true)
  CLIENT_ID=$(      az identity show \
                      --name "$IDENTITY_NAME" \
                      --resource-group "$PLATFORM_RG_VAL" \
                      --query clientId -o tsv 2>/dev/null || true)

  # ── Step 1: Verify az login + ARM token ────────────────────────────────────
  info "Checking Azure login and ARM token..."

  _require_login() {
    blank
    error "${1:-No active Azure session or ARM token expired.}"
    echo  "  Run:  az login"
    echo  "  Then re-run:  bash bootstrap/bootstrap.sh"
    exit 1
  }

  az account show --output none 2>/dev/null \
    || _require_login "No active Azure login session."

  az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null \
    || _require_login "Could not set subscription $SUBSCRIPTION_ID — session may be expired."

  local arm_check_err
  arm_check_err=$(az group list --query "[][name]" -o tsv 2>&1) || {
    if echo "$arm_check_err" | grep -q "AADSTS130507\|access pass\|Interactive authentication"; then
      _require_login "ARM token expired. Run az login."
    else
      _require_login "ARM call failed: $arm_check_err"
    fi
  }

  local ACTIVE_ACCOUNT
  ACTIVE_ACCOUNT=$(az account show --query user.name -o tsv 2>/dev/null || true)
  success "Logged in as: ${ACTIVE_ACCOUNT:-<unknown>}"

  # ── Step 2: Verify platform resource group exists ──────────────────────────
  info "Verifying platform resource group: $PLATFORM_RG_VAL"
  if ! az group show --name "$PLATFORM_RG_VAL" --output none 2>/dev/null; then
    error "Resource group '$PLATFORM_RG_VAL' not found."
    echo  "  Create it first (one-time, permanent):"
    echo  "    az group create --name $PLATFORM_RG_VAL --location $LOCATION"
    exit 1
  fi
  success "Platform resource group confirmed: $PLATFORM_RG_VAL"

  # ── Step 3: Verify Managed Identity exists (in PLATFORM_RG) ─────────────────
  info "Verifying Managed Identity: $IDENTITY_NAME (in $PLATFORM_RG_VAL)"
  local MI_RESOURCE_ID
  MI_RESOURCE_ID=$(az identity show \
    --name "$IDENTITY_NAME" \
    --resource-group "$PLATFORM_RG_VAL" \
    --query id -o tsv 2>/dev/null || true)

  if [[ -z "$MI_RESOURCE_ID" ]]; then
    warn "Managed Identity '$IDENTITY_NAME' not found in '$PLATFORM_RG_VAL'."
    warn "Since the platform RG is shared across all apps, create it manually:"
    echo "  az identity create --name $IDENTITY_NAME --resource-group $PLATFORM_RG_VAL --location $LOCATION"
    exit 1
  fi
  success "Managed Identity confirmed: $IDENTITY_NAME (in $PLATFORM_RG_VAL)"

  # Resolve the MI principal ID (for role assignments later if needed)
  local MI_PRINCIPAL_ID
  MI_PRINCIPAL_ID=$(az identity show \
    --name "$IDENTITY_NAME" \
    --resource-group "$PLATFORM_RG_VAL" \
    --query principalId -o tsv 2>/dev/null || true)

  # ── Step 4: Locate shared Terraform state Storage Account ───────────────────
  # Shared SA: techwizardappstfstate (in techwizard-platformlab-apps)
  # Containers: rentalapp-<env>-tfstate (one per app+env, isolated)
  local STATE_RG="$PLATFORM_RG_VAL"
  info "Locating Terraform state storage account in: $STATE_RG"

  local SA_NAME
  SA_NAME=$(az storage account list \
    --resource-group "$STATE_RG" \
    --query "[?starts_with(name,'techwizardapps')].name" \
    -o tsv 2>/dev/null | head -1 || true)

  if [[ -z "$SA_NAME" ]]; then
    # Fallback: look for legacy twztfstate prefix
    SA_NAME=$(az storage account list \
      --resource-group "$STATE_RG" \
      --query "[?starts_with(name,'twztfstate')].name" \
      -o tsv 2>/dev/null | head -1 || true)
  fi

  if [[ -z "$SA_NAME" ]]; then
    warn "No shared storage account found in '$STATE_RG'."
    warn "Create it manually:"
    echo "  az storage account create --name techwizardappstfstate \\"
    echo "    --resource-group $STATE_RG --location $LOCATION \\"
    echo "    --sku Standard_LRS --kind StorageV2 --https-only true \\"
    echo "    --allow-blob-public-access false --min-tls-version TLS1_2"
    exit 1
  fi
  success "Storage account found: $SA_NAME"

  # ── Step 5: Create per-env blob containers (idempotent) ─────────────────────
  # Pattern: rentalapp-<env>-tfstate  (one container per app+env)
  info "Ensuring blob containers exist for: $GITHUB_REPO"

  _ensure_container() {
    local cname="$1"
    if az storage container create \
        --name         "$cname" \
        --account-name "$SA_NAME" \
        --auth-mode    login \
        --output none 2>/dev/null; then
      success "Container ready: $cname"
    else
      az storage container create \
        --name         "$cname" \
        --account-name "$SA_NAME" \
        --output none 2>/dev/null && success "Container ready: $cname" || \
        warn "Could not create container '$cname' — may already exist or need Storage Blob Data Contributor role"
    fi
  }

  _ensure_container "rentalapp-dev-tfstate"
  _ensure_container "rentalapp-qa-tfstate"

  info "Container layout:"
  info "  rentalapp-dev-tfstate  → infrastructure/azure/environments/dev"
  info "  rentalapp-qa-tfstate   → infrastructure/azure/environments/qa"

  # ── Step 6: OIDC federated credentials on Managed Identity ─────────────────
  blank
  info "Adding OIDC federated credentials to Managed Identity: $IDENTITY_NAME"

  _add_federated_credential() {
    local fc_name="$1"
    local subject="$2"

    local existing
    existing=$(az identity federated-credential list \
      --identity-name "$IDENTITY_NAME" \
      --resource-group "$PLATFORM_RG_VAL" \
      --query "[?name=='${fc_name}'].name" \
      -o tsv 2>/dev/null || true)

    if [[ -n "$existing" ]]; then
      success "Federated credential already exists: $fc_name (skipping)"
      return 0
    fi

    local err_output
    if err_output=$(az identity federated-credential create \
        --identity-name   "$IDENTITY_NAME" \
        --resource-group  "$PLATFORM_RG_VAL" \
        --name            "$fc_name" \
        --issuer          "https://token.actions.githubusercontent.com" \
        --subject         "$subject" \
        --audiences       "api://AzureADTokenExchange" 2>&1); then
      success "Federated credential added: $fc_name"
    else
      warn "Could not add federated credential '$fc_name'."
      warn "Error: $err_output"
    fi
  }

  _add_federated_credential \
    "github-${GITHUB_REPO}-main" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"

  _add_federated_credential \
    "github-${GITHUB_REPO}-pr" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request"

  _add_federated_credential \
    "github-${GITHUB_REPO}-env-approval" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:terraform-destructive-approval"

  # ── Step 7: Grant MI permission to create role assignments ─────────────────
  # Required for Terraform to assign AcrPush/AcrPull/KV roles during apply.
  # Uses User Access Administrator scoped to subscription (idempotent).
  blank
  info "Granting User Access Administrator to MI: $IDENTITY_NAME"
  local SUB_SCOPE="/subscriptions/$SUBSCRIPTION_ID"
  local existing_uaa
  existing_uaa=$(az role assignment list \
    --assignee "$MI_PRINCIPAL_ID" \
    --role "User Access Administrator" \
    --scope "$SUB_SCOPE" \
    --query "[].id" -o tsv 2>/dev/null || true)

  if [[ -n "$existing_uaa" ]]; then
    success "User Access Administrator already assigned — skipping"
  else
    if az role assignment create \
        --role "User Access Administrator" \
        --assignee-object-id "$MI_PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --scope "$SUB_SCOPE" \
        --output none 2>/dev/null; then
      success "User Access Administrator granted to $IDENTITY_NAME"
    else
      warn "Could not assign User Access Administrator — run manually:"
      echo "  az role assignment create \\"
      echo "    --role \"User Access Administrator\" \\"
      echo "    --assignee-object-id $MI_PRINCIPAL_ID \\"
      echo "    --assignee-principal-type ServicePrincipal \\"
      echo "    --scope $SUB_SCOPE"
    fi
  fi

  # ── Step 8: Output GitHub Secrets ──────────────────────────────────────────
  blank
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║  GitHub → Settings → Secrets → Actions                              ║${RESET}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  blank
  echo -e "  ${BOLD}AZURE_CLIENT_ID${RESET}                      = $CLIENT_ID"
  echo -e "  ${BOLD}AZURE_TENANT_ID${RESET}                      = $TENANT_ID"
  echo -e "  ${BOLD}AZURE_SUBSCRIPTION_ID${RESET}                = $SUBSCRIPTION_ID"
  echo -e "  ${BOLD}TF_BACKEND_RG${RESET}                        = $STATE_RG"
  echo -e "  ${BOLD}TF_BACKEND_SA${RESET}                        = $SA_NAME"
  echo -e "  ${BOLD}TF_GITHUB_ACTIONS_PRINCIPAL_ID${RESET}       = $MI_PRINCIPAL_ID"
  blank
  echo -e "  ${BOLD}${YELLOW}Note: Containers are computed per-env — no container secret needed.${RESET}"
  blank
  echo -e "  ${BOLD}State backend layout:${RESET}"
  printf   '    resource_group_name  = "%s"\n' "$STATE_RG"
  printf   '    storage_account_name = "%s"\n' "$SA_NAME"
  printf   '    container (dev)      = "rentalapp-dev-tfstate"\n'
  printf   '    container (qa)       = "rentalapp-qa-tfstate"\n'
  printf   '    key (all)            = "terraform.tfstate"\n'
  blank

  success "Azure bootstrap complete."
}

# =============================================================================
# GCP BOOTSTRAP
# Uses Workload Identity Pool for GitHub Actions OIDC.
# =============================================================================
bootstrap_gcp() {
  header "GCP BOOTSTRAP"

  local failed=0
  require GCP_PROJECT_ID || failed=1
  require GCP_REGION     || failed=1
  require GITHUB_ORG     || failed=1
  require GITHUB_REPO    || failed=1
  [[ "$failed" -eq 0 ]] || { blank; echo "  Fix the above in bootstrap/.env and re-run."; exit 1; }

  local PROJECT_ID="$GCP_PROJECT_ID"
  local REGION="$GCP_REGION"
  local SA_NAME="github-actions-oidc"
  local POOL_ID="github-pool"
  local PROVIDER_ID="github-provider"

  # ── Step 1: Verify GCP login ────────────────────────────────────────────────
  info "Verifying GCP login..."
  local active_account
  active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
  if [[ -z "$active_account" ]]; then
    error "Not logged in to GCP. Run:  gcloud auth login"
    exit 1
  fi
  gcloud config set project "$PROJECT_ID" --quiet
  local PROJECT_NUMBER
  PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
  success "GCP login OK — project: $PROJECT_ID ($PROJECT_NUMBER), account: $active_account"

  # ── Step 2: Enable required APIs ───────────────────────────────────────────
  info "Enabling required GCP APIs (may take ~60s)..."
  gcloud services enable \
    storage.googleapis.com \
    iam.googleapis.com \
    iamcredentials.googleapis.com \
    sts.googleapis.com \
    container.googleapis.com \
    artifactregistry.googleapis.com \
    secretmanager.googleapis.com \
    --project="$PROJECT_ID" --quiet
  success "APIs enabled"

  # ── Step 3: GCS bucket for Terraform state (idempotent) ────────────────────
  local BUCKET_NAME
  BUCKET_NAME=$(gcloud storage buckets list \
    --project="$PROJECT_ID" \
    --format="value(name)" 2>/dev/null \
    | grep "^rentalledger-tfstate" | head -1 || true)

  if [[ -n "$BUCKET_NAME" ]]; then
    success "GCS bucket already exists: $BUCKET_NAME (skipping create)"
  else
    local BUCKET_SUFFIX
    BUCKET_SUFFIX=$(openssl rand -hex 4 2>/dev/null || date +%s | tail -c 8)
    BUCKET_NAME="rentalledger-tfstate-${PROJECT_ID}-${BUCKET_SUFFIX}"
    info "Creating GCS bucket: $BUCKET_NAME"
    gcloud storage buckets create "gs://${BUCKET_NAME}" \
      --project="$PROJECT_ID" \
      --location="$REGION" \
      --uniform-bucket-level-access --quiet
    gcloud storage buckets update "gs://${BUCKET_NAME}" --versioning --quiet
    success "GCS bucket created: $BUCKET_NAME"
  fi

  # ── Step 4: Service Account (reuse if pre-created, else create) ─────────────
  local SA_EMAIL="${GCP_LAB_SA_EMAIL:-}"

  if [[ -n "$SA_EMAIL" && "$SA_EMAIL" != *"<"* ]]; then
    success "Reusing pre-created SA: $SA_EMAIL"
  else
    SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    local sa_exists
    sa_exists=$(gcloud iam service-accounts list \
      --project="$PROJECT_ID" \
      --filter="email=${SA_EMAIL}" \
      --format="value(email)" 2>/dev/null || true)

    if [[ -n "$sa_exists" ]]; then
      success "Service account already exists: $SA_EMAIL (skipping create)"
    else
      info "Creating Service Account: $SA_NAME"
      gcloud iam service-accounts create "$SA_NAME" \
        --display-name="GitHub Actions OIDC — rentalAppLedger" \
        --project="$PROJECT_ID" --quiet
      success "Service account created: $SA_EMAIL"
    fi
  fi

  # ── Step 5: Grant roles to SA ───────────────────────────────────────────────
  info "Granting roles to SA (idempotent)..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/editor" \
    --condition=None --quiet 2>/dev/null || warn "roles/editor already assigned or restricted"

  gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.objectAdmin" --quiet 2>/dev/null || warn "storage.objectAdmin already assigned"
  success "IAM roles granted"

  # ── Step 6: Workload Identity Pool (idempotent) ─────────────────────────────
  local pool_exists
  pool_exists=$(gcloud iam workload-identity-pools list \
    --project="$PROJECT_ID" \
    --location="global" \
    --filter="name:${POOL_ID}" \
    --format="value(name)" 2>/dev/null || true)

  if [[ -n "$pool_exists" ]]; then
    success "Workload Identity Pool already exists: $POOL_ID (skipping)"
  else
    info "Creating Workload Identity Pool: $POOL_ID"
    gcloud iam workload-identity-pools create "$POOL_ID" \
      --project="$PROJECT_ID" --location="global" \
      --display-name="GitHub Actions Pool" --quiet
    success "Pool created: $POOL_ID"
  fi

  # ── Step 7: OIDC Provider (idempotent) ──────────────────────────────────────
  local provider_exists
  provider_exists=$(gcloud iam workload-identity-pools providers list \
    --project="$PROJECT_ID" \
    --location="global" \
    --workload-identity-pool="$POOL_ID" \
    --filter="name:${PROVIDER_ID}" \
    --format="value(name)" 2>/dev/null || true)

  if [[ -n "$provider_exists" ]]; then
    success "OIDC Provider already exists: $PROVIDER_ID (skipping)"
  else
    info "Creating OIDC Provider: $PROVIDER_ID"
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
      --project="$PROJECT_ID" --location="global" \
      --workload-identity-pool="$POOL_ID" \
      --display-name="GitHub Provider" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" \
      --attribute-condition="assertion.repository=='${GITHUB_ORG}/${GITHUB_REPO}'" \
      --quiet
    success "OIDC Provider created: $PROVIDER_ID"
  fi

  # ── Step 8: Bind Workload Identity → SA (idempotent) ───────────────────────
  info "Binding Workload Identity to Service Account..."
  local MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"
  gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="$MEMBER" --quiet 2>/dev/null || warn "Binding may already exist (safe to ignore)"
  success "Workload Identity binding done"

  # ── Step 9: Output GitHub Secrets ──────────────────────────────────────────
  local WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

  blank
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║  GCP — Add these to GitHub → Settings → Secrets → Actions       ║${RESET}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
  blank
  echo -e "  ${BOLD}GCP_PROJECT_ID${RESET}                  = $PROJECT_ID"
  echo -e "  ${BOLD}GCP_WORKLOAD_IDENTITY_PROVIDER${RESET}  = $WIF_PROVIDER"
  echo -e "  ${BOLD}GCP_SERVICE_ACCOUNT${RESET}             = $SA_EMAIL"
  echo -e "  ${BOLD}TF_BACKEND_BUCKET${RESET}               = $BUCKET_NAME"
  echo -e "  ${BOLD}TF_BACKEND_PREFIX${RESET}               = rentalledger/dev"
  blank
  echo -e "  ${BOLD}backend.tf reference:${RESET}"
  printf   '    bucket = "%s"\n' "$BUCKET_NAME"
  printf   '    prefix = "rentalledger/dev"\n'
  blank
  success "GCP bootstrap complete."
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  blank
  echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║   rentalAppLedger — Bootstrap               ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"

  require CLOUD       || { echo "  Set CLOUD=azure|gcp|both in bootstrap/.env"; exit 1; }
  require GITHUB_ORG  || exit 1
  require GITHUB_REPO || exit 1

  select_cloud

  case "$CLOUD_CHOICE" in
    azure) bootstrap_azure ;;
    gcp)   bootstrap_gcp   ;;
    both)  bootstrap_azure; blank; bootstrap_gcp ;;
  esac

  blank
  echo -e "${BOLD}${GREEN}══════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}${GREEN}  Bootstrap complete (cloud: ${CLOUD_CHOICE})${RESET}"
  echo -e "${BOLD}${GREEN}══════════════════════════════════════════════${RESET}"
  blank
  echo "  Next steps:"
  echo "  1. Copy the secrets printed above to GitHub → Settings → Secrets"
  echo "  2. Run set-github-secrets.py to push secrets automatically (optional)"
  echo "  3. Push to main → triggers terraform pipeline"
  blank
}

main "$@"
