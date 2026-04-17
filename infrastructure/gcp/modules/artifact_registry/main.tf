# Artifact Registry — modern replacement for GCR (Container Registry)
# Cost note: storage ~$0.10/GB/month + network egress. For dev, storage is near zero.
# DOCKER format chosen for container image storage.
# IAM bindings (GKE reader, CI writer) are managed in the calling environment module.
resource "google_artifact_registry_repository" "this" {
  repository_id = "${var.environment}-${var.region_short}-docker"
  location      = var.location
  format        = "DOCKER"
  project       = var.project_id
  description   = "Docker images for ${var.environment} — rentalAppLedger"

  labels = var.labels

  # Cleanup policy: keep last 10 images per tag to limit storage cost
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
      older_than = "2592000s" # 30 days in seconds — GCP Duration type requires "Xs" format
    }
  }
}
