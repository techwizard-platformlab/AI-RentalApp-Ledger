# Secret Manager API enablement
# Cost note: Secret Manager is ~$0.06/secret/month + $0.03/10k access operations.
# For 3 secrets in dev, cost is negligible.
resource "google_project_service" "secret_manager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Secrets — values are managed outside Terraform (manual rotation stays free)
# SECURITY: never put actual secret values in Terraform state; use placeholder
# and update via gcloud or CI/CD pipeline after creation.
resource "google_secret_manager_secret" "this" {
  for_each  = toset(var.secret_names)
  secret_id = "${var.environment}-${each.value}"
  project   = var.project_id

  replication {
    auto {}  # auto replication — simpler and sufficient for dev/qa
  }

  labels = var.labels

  depends_on = [google_project_service.secret_manager]
}

# Initial placeholder version — replace with real value via gcloud after apply:
# gcloud secrets versions add {secret_id} --data-file=-
resource "google_secret_manager_secret_version" "placeholder" {
  for_each = google_secret_manager_secret.this

  secret      = each.value.id
  secret_data = "REPLACE_ME"  # placeholder; override manually or via CI/CD
}

# Grant GKE workload identity accessor role so pods can read secrets at runtime
resource "google_secret_manager_secret_iam_member" "gke_accessor" {
  for_each = var.gke_service_account != "" ? google_secret_manager_secret.this : {}

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.gke_service_account}"
}
