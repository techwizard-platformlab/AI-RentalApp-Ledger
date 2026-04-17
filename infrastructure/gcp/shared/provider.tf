terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1"
  # Credentials injected via Workload Identity Federation in GitHub Actions:
  # GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT — no JSON key file
}
