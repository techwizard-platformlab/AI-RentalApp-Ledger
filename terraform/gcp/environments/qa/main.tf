# =============================================================================
# qa environment — mirrors dev with slightly higher resource limits
# Naming: qa-use1-{resource}
# =============================================================================

locals {
  env          = "qa"
  region_short = "use1"
  region       = "us-central1"
  labels = {
    env     = local.env
    project = "rentalappledger"
    owner   = "ramprasath"
  }
}

module "vpc" {
  source       = "../../modules/vpc"
  project_id   = var.project_id
  environment  = local.env
  region       = local.region
  region_short = local.region_short

  app_subnet_cidr = "10.4.1.0/24"  # non-overlapping with dev
  db_subnet_cidr  = "10.4.2.0/24"
  pods_cidr       = "10.5.0.0/16"
  services_cidr   = "10.6.0.0/20"
}

module "cloud_armor" {
  source       = "../../modules/cloud_armor"
  project_id   = var.project_id
  environment  = local.env
  region_short = local.region_short
}

module "gke" {
  source       = "../../modules/gke"
  project_id   = var.project_id
  environment  = local.env
  region       = local.region
  region_short = local.region_short

  network_name         = module.vpc.network_name
  subnet_name          = module.vpc.app_subnet_name
  pods_range_name      = module.vpc.pods_range_name
  services_range_name  = module.vpc.services_range_name

  master_ipv4_cidr = "172.16.1.0/28"  # non-overlapping with dev
  master_authorized_cidrs = [
    { cidr_block = "0.0.0.0/0", display_name = "all — restrict in prod" }
  ]

  node_count   = 1              # still 1 node for KodeKloud quota
  machine_type = "e2-standard-2"
  disk_size_gb = 30

  labels = local.labels
}

module "artifact_registry" {
  source       = "../../modules/artifact_registry"
  project_id   = var.project_id
  environment  = local.env
  region_short = local.region_short
  location     = local.region

  gke_service_account = module.gke.node_service_account_email
  labels              = local.labels
}

# --- Database -----------------------------------------------------------------
module "cloud_sql" {
  source       = "../../modules/cloud_sql"
  project_id   = var.project_id
  environment  = local.env
  region       = local.region
  region_short = local.region_short

  vpc_network_id      = module.vpc.network_id
  db_tier             = "db-g1-small"   # slightly larger for qa load tests
  gke_service_account = module.gke.node_service_account_email
  labels              = local.labels

  depends_on = [module.vpc]
}

# --- Secrets (non-DB) ---------------------------------------------------------
module "secret_manager" {
  source       = "../../modules/secret_manager"
  project_id   = var.project_id
  environment  = local.env

  secret_names        = ["acr-token", "discord-webhook"]
  gke_service_account = module.gke.node_service_account_email
  labels              = local.labels
}

module "storage_bucket" {
  source      = "../../modules/storage_bucket"
  project_id  = var.project_id
  environment = local.env
  suffix      = "app-data"
  location    = "US"
  labels      = local.labels
}

module "workload_identity" {
  source      = "../../modules/workload_identity"
  project_id  = var.project_id
  environment = local.env
  github_org  = var.github_org
  github_repo = var.github_repo
}
