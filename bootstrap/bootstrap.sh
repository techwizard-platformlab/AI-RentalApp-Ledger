#!/usr/bin/env bash
# =============================================================================
# rentalAppLedger — Unified Bootstrap Script (KodeKloud-aware)
#
# KodeKloud hard constraints respected:
#   - Does NOT attempt role assignment (pre-granted by KodeKloud internally)
#   - Does NOT create resource groups (uses the pre-existing one)
#   - Does NOT attempt non-interactive / password-based Azure login
#   - Uses the pre-existing SP (AZURE_APP_ID) for GitHub Actions auth
#
# Azure auth strategy:
#   PRIMARY  — OIDC federated credentials on pre-existing SP (best-effort add)
#   FALLBACK — Client secret on pre-existing SP (set AZURE_CLIENT_SECRET)
#
# GCP   — pre-existing project, Workload Identity Pool for GitHub Actions OIDC
#
# Setup:
#   cp bootstrap/.env.example bootstrap/.env
#   # Fill in bootstrap/.env with your KodeKloud lab values
#   az login                        # for Azure; browser-based, once per session
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
  echo "  Then fill in your KodeKloud lab values and re-run."
  exit 1
fi

# Safe .env loader
# Handles: special chars (~,+,=,%,@), inline comments, surrounding quotes,
#          trailing whitespace, quoted values with trailing comments.
load_env() {
  local file="$1"
  while IFS= read -r line; do
    # Skip blank lines and full-line comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Must contain '='
    [[ "$line" != *"="* ]] && continue

    local key="${line%%=*}"
    local val="${line#*=}"

    # Trim whitespace from key
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    # Skip invalid keys
    [[ -z "$key" || ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && continue

    # Strip surrounding quotes FIRST (before comment removal)
    # Handles: "value"   'value'   "value with spaces"  # comment
    if [[ "$val" =~ ^[[:space:]]*\"([^\"]*)\" ]]; then
      val="${BASH_REMATCH[1]}"
    elif [[ "$val" =~ ^[[:space:]]*\'([^\']*)\' ]]; then
      val="${BASH_REMATCH[1]}"
    else
      # Unquoted value — strip inline comment (# preceded by whitespace)
      val="${val%%[[:space:]]#*}"
      # Trim trailing whitespace
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
  echo    "  AZURE_SUBSCRIPTION_ID = ${AZURE_SUBSCRIPTION_ID:-<not set>}"
  echo    "  AZURE_TENANT_ID       = ${AZURE_TENANT_ID:-<not set>}"
  echo    "  AZURE_APP_ID          = ${AZURE_APP_ID:-<not set>}"
  echo    "  AZURE_RG              = ${AZURE_RG:-<not set>}"
  echo    "  AZURE_LOCATION        = ${AZURE_LOCATION:-<not set>}"
  echo    "  AZURE_LAB_USERNAME    = ${AZURE_LAB_USERNAME:-<not set>}"
  local cs="${AZURE_CLIENT_SECRET:-}"
  [[ -n "$cs" ]] && echo "  AZURE_CLIENT_SECRET   = ${cs:0:4}****" \
                 || echo "  AZURE_CLIENT_SECRET   = <not set>"
  blank
}

# Show debug if --debug flag passed OR if BOOTSTRAP_DEBUG=1 in .env
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
  # Normalise: trim whitespace, strip quotes, lowercase
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
      echo  "  Tip: set CLOUD=azure  (no quotes, no inline comment on same line)"
      exit 1 ;;
  esac
  info "Cloud: ${BOLD}${CLOUD_CHOICE}${RESET}"
}

# =============================================================================
# AZURE BOOTSTRAP
#
# KodeKloud constraints applied:
#   - No role assignment (pre-granted by KodeKloud)
#   - No RG creation (uses existing)
#   - No non-interactive login (az login required beforehand)
#   - Uses pre-existing SP (AZURE_APP_ID) for auth
# =============================================================================
bootstrap_azure() {
  header "AZURE BOOTSTRAP"

  # ── Validate required .env variables ───────────────────────────────────────
  local failed=0
  require AZURE_SUBSCRIPTION_ID || failed=1
  require AZURE_TENANT_ID       || failed=1
  require AZURE_APP_ID          || failed=1
  require AZURE_RG              || failed=1
  require AZURE_LOCATION        || failed=1
  require GITHUB_ORG            || failed=1
  require GITHUB_REPO           || failed=1
  [[ "$failed" -eq 0 ]] || { blank; echo "  Fix the above in bootstrap/.env and re-run."; exit 1; }

  local RG="$AZURE_RG"
  local LOCATION="$AZURE_LOCATION"
  local APP_ID="$AZURE_APP_ID"
  local SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
  local TENANT_ID="$AZURE_TENANT_ID"
  local CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"
  local CONTAINER_NAME="tfstate"

  # ── Step 1: Verify az login + ARM token ────────────────────────────────────
  # az account show can succeed with a stale cached session while actual ARM
  # calls fail with AADSTS130507. We validate the ARM token explicitly.
  info "Checking Azure login and ARM token..."

  _require_login() {
    blank
    error "${1:-No active Azure session or ARM token expired.}"
    echo  "  ┌──────────────────────────────────────────────────────────────┐"
    echo  "  │  Run this in your terminal, then re-run bootstrap:           │"
    echo  "  │                                                              │"
    echo  "  │    az login                                                  │"
    echo  "  │                                                              │"
    echo  "  │  Browser will open — sign in with KodeKloud lab credentials. │"
    echo  "  │  After login completes, re-run:                              │"
    echo  "  │    bash bootstrap/bootstrap.sh                               │"
    echo  "  └──────────────────────────────────────────────────────────────┘"
    exit 1
  }

  # Check basic session
  az account show --output none 2>/dev/null \
    || _require_login "No active Azure login session."

  # Set subscription first so the token check uses the right scope
  az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null \
    || _require_login "Could not set subscription $SUBSCRIPTION_ID — session may be expired."

  # Validate ARM token by making a real ARM call (list RGs — cheapest read)
  local arm_check_err
  arm_check_err=$(az group list --query "[][name]" -o tsv 2>&1) || {
    if echo "$arm_check_err" | grep -q "AADSTS130507\|access pass\|Interactive authentication"; then
      _require_login "ARM token expired (AADSTS130507). Need fresh az login."
    else
      _require_login "ARM call failed: $arm_check_err"
    fi
  }

  local ACTIVE_ACCOUNT
  ACTIVE_ACCOUNT=$(az account show --query user.name -o tsv 2>/dev/null || true)
  success "Logged in as: ${ACTIVE_ACCOUNT:-<unknown>}"

  # ── Step 2: Confirm subscription ───────────────────────────────────────────
  local CONFIRMED_SUB
  CONFIRMED_SUB=$(az account show --query id -o tsv)
  if [[ "$CONFIRMED_SUB" != "$SUBSCRIPTION_ID" ]]; then
    error "Subscription mismatch: expected '$SUBSCRIPTION_ID', got '$CONFIRMED_SUB'"
    exit 1
  fi
  success "Active subscription confirmed: $SUBSCRIPTION_ID"

  # Resolve tenant GUID from the active session (handles domain or GUID input)
  local SESSION_TENANT
  SESSION_TENANT=$(az account show --query tenantId -o tsv 2>/dev/null || true)
  [[ -n "$SESSION_TENANT" ]] && TENANT_ID="$SESSION_TENANT"

  # ── Step 3: Create Terraform state Storage Account (idempotent) ─────────────
  info "Checking for existing Terraform state storage account in RG: $RG"

  local SA_NAME
  SA_NAME=$(az storage account list \
    --resource-group "$RG" \
    --query "[?starts_with(name,'rentalledgertf')].name" \
    -o tsv 2>/dev/null | head -1 || true)

  if [[ -n "$SA_NAME" ]]; then
    success "Storage account already exists: $SA_NAME (skipping create)"
  else
    local SA_SUFFIX
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

  # ── Step 4: Create blob container (idempotent) ──────────────────────────────
  info "Ensuring blob container exists: $CONTAINER_NAME"

  # Try RBAC auth first; fall back to key-based if RBAC not ready yet
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

  # ── Step 5: Best-effort OIDC federated credentials on existing SP ───────────
  # Role assignments are intentionally NOT attempted here.
  # KodeKloud internally pre-grants the pre-existing SP Contributor access.
  blank
  info "Attempting to add OIDC federated credentials to SP: $APP_ID (best-effort)"
  warn "Role assignments are SKIPPED — KodeKloud pre-grants SP access to the RG."

  _add_federated_credential() {
    local fc_name="$1"
    local subject="$2"

    local existing
    existing=$(az ad app federated-credential list \
      --id "$APP_ID" \
      --query "[?name=='${fc_name}'].name" \
      -o tsv 2>/dev/null || true)

    if [[ -n "$existing" ]]; then
      success "Federated credential already exists: $fc_name (skipping)"
      return 0
    fi

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
      warn "Use the client-secret fallback shown in the secrets output below."
    fi
  }

  _add_federated_credential \
    "github-main" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"

  _add_federated_credential \
    "github-pr" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request"

  # ── Step 6: Output GitHub Secrets ──────────────────────────────────────────
  blank
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║  AZURE — GitHub → Settings → Secrets → Actions                      ║${RESET}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  blank

  # Option A: OIDC
  echo -e "  ${BOLD}${CYAN}Option A — OIDC / Federated Credentials (preferred, no expiry)${RESET}"
  echo -e "  Use if federated credentials were added successfully above."
  echo -e "  GitHub Actions workflow needs: permissions: id-token: write"
  blank
  echo -e "  ${BOLD}AZURE_CLIENT_ID${RESET}        = $APP_ID"
  echo -e "  ${BOLD}AZURE_TENANT_ID${RESET}        = $TENANT_ID"
  echo -e "  ${BOLD}AZURE_SUBSCRIPTION_ID${RESET}  = $SUBSCRIPTION_ID"
  echo -e "  ${BOLD}TF_BACKEND_RG${RESET}          = $RG"
  echo -e "  ${BOLD}TF_BACKEND_SA${RESET}          = $SA_NAME"
  echo -e "  ${BOLD}TF_BACKEND_CONTAINER${RESET}   = $CONTAINER_NAME"
  blank

  # Option B: Client Secret fallback
  echo -e "  ${BOLD}${YELLOW}Option B — Client Secret fallback (expires each KodeKloud session)${RESET}"
  echo -e "  Use if OIDC did not work or federated credential creation was denied."
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
    echo -e "                          → Copy Value immediately; set AZURE_CLIENT_SECRET"
    echo -e "                          → Re-run bootstrap.sh to see it printed here"
  fi

  echo -e "  ${BOLD}TF_BACKEND_RG${RESET}          = $RG"
  echo -e "  ${BOLD}TF_BACKEND_SA${RESET}          = $SA_NAME"
  echo -e "  ${BOLD}TF_BACKEND_CONTAINER${RESET}   = $CONTAINER_NAME"
  blank

  echo -e "  ${BOLD}terraform/azure/backend.tf:${RESET}"
  printf   '    resource_group_name  = "%s"\n' "$RG"
  printf   '    storage_account_name = "%s"\n' "$SA_NAME"
  printf   '    container_name       = "%s"\n' "$CONTAINER_NAME"
  printf   '    key                  = "dev.terraform.tfstate"\n'
  blank

  echo -e "  ${BOLD}${YELLOW}KodeKloud reminders:${RESET}"
  echo    "  - Role assignments are pre-granted by KodeKloud internally."
  echo    "    Do NOT run az role assignment create — it will be rejected."
  echo    "  - Client secrets expire at the end of each lab session."
  echo    "    Regenerate and update GitHub secrets on each new session."
  echo    "  - OIDC federated credentials do not expire — prefer Option A."
  blank

  success "Azure bootstrap complete."
}

# =============================================================================
# GCP BOOTSTRAP
# KodeKloud notes:
#   - Uses pre-existing GCP project (cannot create new projects)
#   - Creates Workload Identity Pool for GitHub Actions OIDC
#   - If GCP_LAB_SA_EMAIL is set in .env, reuses that SA; otherwise creates one
#   - US regions only
# =============================================================================
bootstrap_gcp() {
  header "GCP BOOTSTRAP"

  # ── Validate required .env variables ───────────────────────────────────────
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

  # ── Step 4: Service Account (reuse if KodeKloud pre-created, else create) ──
  local SA_EMAIL="${GCP_LAB_SA_EMAIL:-}"

  if [[ -n "$SA_EMAIL" && "$SA_EMAIL" != *"<"* ]]; then
    success "Reusing KodeKloud pre-created SA: $SA_EMAIL"
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
  echo -e "  ${BOLD}terraform/gcp/backend.tf:${RESET}"
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
  echo -e "${BOLD}║   rentalAppLedger — Bootstrap (KodeKloud)    ║${RESET}"
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
  echo "  2. git push origin main  →  triggers terraform pipeline"
  blank
}

main "$@"
