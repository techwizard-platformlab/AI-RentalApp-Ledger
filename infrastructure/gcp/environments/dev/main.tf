# =============================================================================
# GCP dev environment — composes all GCP modules with dev-specific values.
#
# Artifact Registry is shared — IAM bindings (reader/writer) managed here.
# Secret Manager, GKE, VPC, Cloud SQL, and Storage are env-specific.
# =============================================================================

# ── Networking ────────────────────────────────────────────────────────────────
module "vpc" {
  source       = "../../modules/vpc"
  project_id   = var.project_id
  environment  = var.environment
  region       = var.region
  region_short = var.region_short

  app_subnet_cidr = var.app_subnet_cidr
  db_subnet_cidr  = var.db_subnet_cidr
  pods_cidr       = var.pods_cidr
  services_cidr   = var.services_cidr
}

# ── Security ──────────────────────────────────────────────────────────────────
module "cloud_armor" {
  source       = "../../modules/cloud_armor"
  project_id   = var.project_id
  environment  = var.environment
  region_short = var.region_short
}

# ── Compute ───────────────────────────────────────────────────────────────────
module "gke" {
  source       = "../../modules/gke"
  project_id   = var.project_id
  environment  = var.environment
  region       = var.region
  region_short = var.region_short

  network_name        = module.vpc.network_name
  subnet_name         = module.vpc.app_subnet_name
  pods_range_name     = module.vpc.pods_range_name
  services_range_name = module.vpc.services_range_name

  cluster_location        = var.cluster_location
  master_ipv4_cidr        = var.master_ipv4_cidr
  master_authorized_cidrs = var.master_authorized_cidrs

  node_count   = var.gke_node_count
  machine_type = var.gke_machine_type
  disk_size_gb = var.gke_disk_size_gb

  labels = local.labels
}

# ── Shared Artifact Registry IAM ──────────────────────────────────────────────
# GKE node SA can pull images from the shared registry
resource "google_artifact_registry_repository_iam_member" "gke_reader" {
  project    = var.project_id
  location   = var.ar_location
  repository = var.ar_repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${module.gke.node_service_account_email}"
}

# CI/CD SA can push images to the shared registry
resource "google_artifact_registry_repository_iam_member" "ci_writer" {
  project    = var.project_id
  location   = var.ar_location
  repository = var.ar_repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${module.workload_identity.service_account_email}"
}

# ── Database ──────────────────────────────────────────────────────────────────
module "cloud_sql" {
  source       = "../../modules/cloud_sql"
  project_id   = var.project_id
  environment  = var.environment
  region       = var.region
  region_short = var.region_short

  vpc_network_id        = module.vpc.network_id
  vpc_network_self_link = module.vpc.network_self_link
  db_tier               = var.db_tier
  gke_service_account   = module.gke.node_service_account_email
  labels                = local.labels

  depends_on = [module.vpc]
}

# ── Secrets ───────────────────────────────────────────────────────────────────
module "secret_manager" {
  source      = "../../modules/secret_manager"
  project_id  = var.project_id
  environment = var.environment

  secret_names        = ["discord-webhook"]
  gke_service_account = module.gke.node_service_account_email
  labels              = local.labels
}

# Artifact Registry URL secret — consumed by app pods at runtime
resource "google_secret_manager_secret" "ar_url" {
  secret_id = "${var.environment}-artifact-registry-url"
  project   = var.project_id

  replication {
    auto {}
  }

  labels     = local.labels
  depends_on = [module.secret_manager]
}

resource "google_secret_manager_secret_version" "ar_url" {
  secret      = google_secret_manager_secret.ar_url.id
  secret_data = "${var.ar_location}-docker.pkg.dev/${var.project_id}/${var.ar_repository_id}"
}

resource "google_secret_manager_secret_iam_member" "gke_ar_url_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.ar_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.gke.node_service_account_email}"
}

# ── Storage ───────────────────────────────────────────────────────────────────
module "storage_bucket" {
  source      = "../../modules/storage_bucket"
  project_id  = var.project_id
  environment = var.environment
  suffix      = "app-data"
  location    = var.storage_bucket_location
  labels      = local.labels
}

# ── Workload Identity (GitHub Actions OIDC) ───────────────────────────────────
module "workload_identity" {
  source      = "../../modules/workload_identity"
  project_id  = var.project_id
  environment = var.environment
  github_org  = var.github_org
  github_repo = var.github_repo
}
