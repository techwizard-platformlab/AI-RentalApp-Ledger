# =============================================================================
# Terraform GCP Remote State Backend — dev environment
# Values are populated after running bootstrap/gcp/bootstrap.sh
# =============================================================================

terraform {
  backend "gcs" {
    bucket = "<TF_BACKEND_BUCKET>"   # from bootstrap output
    prefix = "rentalledger/dev"
  }
}
