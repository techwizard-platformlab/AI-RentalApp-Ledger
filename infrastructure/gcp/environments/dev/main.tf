# =============================================================================
# dev environment — composes all GCP modules with dev-specific values
# Naming: dev-use1-{resource}
#
# Artifact Registry is shared — IAM bindings (reader/writer) managed here.
# Secret Manager, GKE, VPC, Cloud SQL are env-specific.
# =============================================================================

locals {
  env          = "dev"
  region_short = "use1"
  region       = "us-central1"
  labels = {
    env     = local.env
    project = "rentalappledger"
    owner   = "ramprasath"
  }
}

# --- Networking ---------------------------------------------------------------
module "vpc" {
  source       = "../../modules/vpc"
  project_id   = var.project_id
  environment  = local.env
  region       = local.region
  region_short = local.region_short

  app_subnet_cidr = "10.1.1.0/24"
  db_subnet_cidr  = "10.1.2.0/24"
  pods_cidr       = "10.2.0.0/16"
  services_cidr   = "10.3.0.0/20"
}

# --- Security -----------------------------------------------------------------
module "cloud_armor" {
  source       = "../../modules/cloud_armor"
  project_id   = var.project_id
  environment  = local.env
  region_short = local.region_short
}

# --- Compute ------------------------------------------------------------------
module "gke" {
  source       = "../../modules/gke"
  project_id   = var.project_id
  environment  = local.env
  region       = local.region
  region_short = local.region_short

  network_name        = module.vpc.network_name
  subnet_name         = module.vpc.app_subnet_name
  pods_range_name     = module.vpc.pods_range_name
  services_range_name = module.vpc.services_range_name

  cluster_location = "us-central1-a"
  master_ipv4_cidr = "172.16.0.0/28"
  master_authorized_cidrs = [
    { cidr_block = "0.0.0.0/0", display_name = "all — restrict in prod" }
  ]

  node_count   = 1
  machine_type = "e2-standard-2"
  disk_size_gb = 30

  labels = local.labels
}

# --- Shared Artifact Registry IAM --------------------------------------------
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

# --- Database -----------------------------------------------------------------
module "cloud_sql" {
  source       = "../../modules/cloud_sql"
  project_id   = var.project_id
  environment  = local.env
  region       = local.region
  region_short = local.region_short

  vpc_network_id        = module.vpc.network_id
  vpc_network_self_link = module.vpc.network_self_link
  db_tier               = "db-f1-micro"
  gke_service_account   = module.gke.node_service_account_email
  labels                = local.labels

  depends_on = [module.vpc]
}

# --- Secrets ------------------------------------------------------------------
module "secret_manager" {
  source      = "../../modules/secret_manager"
  project_id  = var.project_id
  environment = local.env

  secret_names        = ["discord-webhook"]
  gke_service_account = module.gke.node_service_account_email
  labels              = local.labels
}

# Artifact Registry URL — written at apply time with the actual URL
resource "google_secret_manager_secret" "ar_url" {
  secret_id = "${local.env}-artifact-registry-url"
  project   = var.project_id

  replication {
    auto {}
  }

  labels     = local.labels
  depends_on = [module.secret_manager] # ensures Secret Manager API is enabled
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

# --- Storage ------------------------------------------------------------------
module "storage_bucket" {
  source      = "../../modules/storage_bucket"
  project_id  = var.project_id
  environment = local.env
  suffix      = "app-data"
  location    = "US"
  labels      = local.labels
}

# --- Workload Identity (GitHub Actions OIDC) ----------------------------------
module "workload_identity" {
  source      = "../../modules/workload_identity"
  project_id  = var.project_id
  environment = local.env
  github_org  = var.github_org
  github_repo = var.github_repo
}
