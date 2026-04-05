# =============================================================================
# Workload Identity Federation for GitHub Actions OIDC
#
# Why OIDC over JSON keys:
#   JSON service account keys are long-lived credentials that can be leaked via
#   logs, git history, or misconfigured storage. Workload Identity Federation
#   exchanges a short-lived GitHub OIDC token (valid ~5 min) for a GCP access
#   token — no static secret is ever stored in GitHub or the repo.
# =============================================================================

# Enable required APIs
resource "google_project_service" "iam_credentials" {
  project            = var.project_id
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sts" {
  project            = var.project_id
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

# Workload Identity Pool — logical container for external identity providers
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions-pool"
  project                   = var.project_id
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions OIDC"

  depends_on = [google_project_service.sts]
}

# OIDC Provider — maps GitHub JWT claims to Google attributes
resource "google_iam_workload_identity_pool_provider" "github_oidc" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  project                            = var.project_id
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # Map GitHub JWT claims to Google attributes
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Only allow tokens from the specific GitHub repo (security constraint)
  attribute_condition = "attribute.repository == \"${var.github_org}/${var.github_repo}\""
}

# Service Account for Terraform CI/CD pipeline
# Security note: roles/editor is broad — restrict to specific roles in prod.
resource "google_service_account" "terraform_ci" {
  account_id   = "${var.environment}-terraform-ci-sa"
  display_name = "Terraform CI SA — ${var.environment}"
  project      = var.project_id
}

# IAM roles for the Terraform SA
resource "google_project_iam_member" "terraform_editor" {
  project = var.project_id
  role    = "roles/editor"  # broad for dev/learning; restrict in prod
  member  = "serviceAccount:${google_service_account.terraform_ci.email}"
}

resource "google_project_iam_member" "terraform_container_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.terraform_ci.email}"
}

resource "google_project_iam_member" "terraform_secret_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.terraform_ci.email}"
}

# Bind the Workload Identity Pool to the service account
# This allows GitHub Actions jobs matching the condition to impersonate the SA
resource "google_service_account_iam_member" "github_wi_binding" {
  service_account_id = google_service_account.terraform_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}
