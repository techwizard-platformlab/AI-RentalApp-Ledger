# Artifact Registry — modern replacement for GCR (Container Registry)
# Cost note: storage ~$0.10/GB/month + network egress. For dev, storage is near zero.
# DOCKER format chosen for container image storage.
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
      older_than = "720h"  # delete untagged images older than 30 days
    }
  }
}

# Grant GKE service account pull access to the registry
resource "google_artifact_registry_repository_iam_member" "gke_reader" {
  count = var.gke_service_account != "" ? 1 : 0

  project    = var.project_id
  location   = var.location
  repository = google_artifact_registry_repository.this.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.gke_service_account}"
}
