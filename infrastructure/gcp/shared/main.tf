# =============================================================================
# Shared GCP infrastructure — applied ONCE, rarely changed.
# Contains:
#   Artifact Registry — single shared Docker registry; images promoted dev → qa by tag
#
# Does NOT contain:
#   Secret Manager — each environment manages its own (see environments/)
#   GCS state bucket — bootstrap-created (see bootstrap/gcp/)
#
# IAM bindings (GKE reader, CI writer) are managed per-environment so each
# env grants its own GKE node SA and CI SA access after those SAs are created.
#
# Apply:
#   cd infrastructure/gcp/shared
#   terraform init -backend-config=...
#   terraform apply
# =============================================================================

locals {
  location     = "us-central1"
  region_short = "use1"

  labels = {
    project = "rentalappledger"
    tier    = "shared"
    managed = "terraform"
  }
}

resource "google_artifact_registry_repository" "shared" {
  repository_id = "shared-${local.region_short}-docker"
  location      = local.location
  format        = "DOCKER"
  project       = var.project_id
  description   = "Shared Docker registry — images promoted dev → qa by tag"

  labels = local.labels

  cleanup_policies {
    id     = "keep-last-10"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "2592000s"
    }
  }
}
