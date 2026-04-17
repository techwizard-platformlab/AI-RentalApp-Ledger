# =============================================================================
# GCP dev — non-secret environment config
# Committed to git. Secrets injected by GitHub Actions as TF_VAR_* env vars:
#   TF_VAR_project_id  → GCP_PROJECT_ID
# =============================================================================

# ── Environment identity ──────────────────────────────────────────────────────
environment  = "dev"
region       = "us-central1"
region_short = "use1"
project      = "rentalappledger"
owner        = "ramprasath"

# ── GitHub OIDC ───────────────────────────────────────────────────────────────
github_org  = "ramprasath-technology"
github_repo = "AI-RentalApp-Ledger"

# ── Shared Artifact Registry (from gcp/shared/ outputs) ──────────────────────
ar_repository_id = "shared-use1-docker"
ar_location      = "us-central1"

# ── Networking ────────────────────────────────────────────────────────────────
app_subnet_cidr = "10.1.1.0/24"
db_subnet_cidr  = "10.1.2.0/24"
pods_cidr       = "10.2.0.0/16"
services_cidr   = "10.3.0.0/20"

# ── Compute ───────────────────────────────────────────────────────────────────
cluster_location = "us-central1-a"
master_ipv4_cidr = "172.16.0.0/28"
master_authorized_cidrs = [
  { cidr_block = "0.0.0.0/0", display_name = "all — restrict in prod" }
]
gke_node_count   = 1
gke_machine_type = "e2-standard-2"
gke_disk_size_gb = 30

# ── Database ──────────────────────────────────────────────────────────────────
db_tier = "db-f1-micro"

# ── Storage ───────────────────────────────────────────────────────────────────
storage_bucket_location = "US"
