# =============================================================================
# GCP qa — non-secret environment config
# Committed to git. Secrets are injected by GitHub Actions as TF_VAR_* env vars:
#   TF_VAR_project_id  → GitHub Secret: GCP_PROJECT_ID
# =============================================================================

environment = "qa"
region      = "us-central1"
github_org  = "ramprasath-technology"
github_repo = "AI-RentalApp-Ledger"

# From gcp/shared/ outputs — populated after first shared apply
ar_repository_id = "shared-use1-docker"
ar_location      = "us-central1"
