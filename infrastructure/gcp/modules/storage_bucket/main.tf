# GCS Bucket — STANDARD class, US multi-region for Terraform state durability
# Cost note: STANDARD US multi-region ~$0.026/GB/month.
# Nearline/Coldline would be cheaper but have retrieval fees — wrong fit for tfstate.
resource "google_storage_bucket" "this" {
  name          = "${var.project_id}-${var.environment}-${var.suffix}"  # globally unique
  location      = var.location  # "US" = multi-region; cheapest per-GB for frequently accessed data
  project       = var.project_id
  storage_class = "STANDARD"

  # Versioning keeps every tfstate revision — critical for state recovery
  versioning {
    enabled = true
  }

  # Lifecycle: delete non-current versions older than 30 days to control storage cost
  lifecycle_rule {
    condition {
      age                = 30
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Prevent accidental public access
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Force HTTPS
  # (GCS enforces HTTPS by default; this is belt-and-suspenders)

  labels = var.labels
}
