#!/usr/bin/env bash
# =============================================================================
# Prompt 0.1 — Bootstrap: GCP State Backend + Workload Identity (OIDC)
# Project: rentalAppLedger
# Run ONCE per KodeKloud session.
# IMPORTANT: Uses default project only — cannot create new GCP projects.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# INPUTS — fill these before running
# ---------------------------------------------------------------------------
GITHUB_ORG="<your-github-org-or-username>"
GITHUB_REPO="AI-RentalApp-Ledger"
REGION="us-central1"                          # KodeKloud: US regions only
BUCKET_SUFFIX="$RANDOM"

# Derived
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
BUCKET_NAME="rentalledger-tfstate-${PROJECT_ID}-${BUCKET_SUFFIX}"
SA_NAME="github-actions-oidc"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
POOL_ID="github-pool"
PROVIDER_ID="github-provider"

echo "==> Using GCP project: $PROJECT_ID ($PROJECT_NUMBER)"

# ---------------------------------------------------------------------------
# 1. Enable required APIs
# ---------------------------------------------------------------------------
echo "==> Enabling required APIs"
gcloud services enable \
  storage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  --project="$PROJECT_ID"

# ---------------------------------------------------------------------------
# 2. Create GCS bucket for Terraform state with versioning
# ---------------------------------------------------------------------------
echo "==> Creating GCS bucket: $BUCKET_NAME"
gcloud storage buckets create "gs://${BUCKET_NAME}" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --uniform-bucket-level-access

echo "==> Enabling versioning on bucket"
gcloud storage buckets update "gs://${BUCKET_NAME}" \
  --versioning

# Prevent public access
gcloud storage buckets update "gs://${BUCKET_NAME}" \
  --no-pap-override 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Print GCP backend outputs
# ---------------------------------------------------------------------------
echo ""
echo "=== GCP Backend Outputs (paste into terraform/gcp/backend.tf) ==="
echo "  bucket  = \"$BUCKET_NAME\""
echo "  prefix  = \"rentalledger/dev\""

# ---------------------------------------------------------------------------
# 4. Create Service Account for GitHub Actions (no JSON keys)
# ---------------------------------------------------------------------------
echo ""
echo "==> Creating Service Account: $SA_NAME"
gcloud iam service-accounts create "$SA_NAME" \
  --display-name="GitHub Actions OIDC — rentalAppLedger" \
  --project="$PROJECT_ID"

# Grant editor on default project (KodeKloud cannot create IAM org policies)
echo "==> Granting roles/editor to Service Account"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/editor" \
  --condition=None

# Grant storage admin for Terraform state bucket
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectAdmin"

# ---------------------------------------------------------------------------
# 5. Create Workload Identity Pool + Provider for GitHub Actions OIDC
# ---------------------------------------------------------------------------
echo "==> Creating Workload Identity Pool: $POOL_ID"
gcloud iam workload-identity-pools create "$POOL_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions Pool"

echo "==> Creating OIDC Provider: $PROVIDER_ID"
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --display-name="GitHub Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" \
  --attribute-condition="assertion.repository=='${GITHUB_ORG}/${GITHUB_REPO}'"

# ---------------------------------------------------------------------------
# 6. Allow GitHub Actions to impersonate the Service Account
# ---------------------------------------------------------------------------
POOL_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"

echo "==> Binding Workload Identity to Service Account"
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="$MEMBER"

# ---------------------------------------------------------------------------
# 7. Print GitHub Actions secrets (GCP)
# ---------------------------------------------------------------------------
WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

echo ""
echo "=== GitHub Actions Secrets — GCP (add to repo Settings > Secrets) ==="
echo "  GCP_PROJECT_ID           = $PROJECT_ID"
echo "  GCP_WORKLOAD_IDENTITY_PROVIDER = $WIF_PROVIDER"
echo "  GCP_SERVICE_ACCOUNT      = $SA_EMAIL"
echo ""
echo "  TF_BACKEND_BUCKET        = $BUCKET_NAME"
echo "  TF_BACKEND_PREFIX        = rentalledger/dev"
echo ""
echo "==> GCP bootstrap complete."
