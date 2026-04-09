# =============================================================================
# GCP dev — non-secret environment config
# Committed to git. Secrets are injected by GitHub Actions as TF_VAR_* env vars:
#   TF_VAR_project_id  → GitHub Secret: GCP_PROJECT_ID
# =============================================================================

environment = "dev"
region      = "us-central1"
github_org  = "ramprasath-technology"
github_repo = "AI-RentalApp-Ledger"
