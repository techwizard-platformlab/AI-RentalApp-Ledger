# =============================================================================
# Variable sources:
#   terraform.tfvars (committed)  → environment, region, region_short, project,
#                                   owner, github_org, github_repo,
#                                   networking, compute, database, storage,
#                                   ar_repository_id, ar_location
#   GitHub Secret → TF_VAR_*     → project_id
# =============================================================================

variable "environment" {
  description = "Deployment environment — set in terraform.tfvars."
  type        = string
  validation {
    condition     = contains(["dev", "qa", "uat", "prod"], var.environment)
    error_message = "Must be one of: dev, qa, uat, prod."
  }
}

variable "region" {
  description = "GCP region for all resources in this environment."
  type        = string
  default     = "us-central1"
}

variable "region_short" {
  description = "Short region code used in resource name suffixes (e.g. use1)."
  type        = string
}

variable "project" {
  description = "Project label applied to all GCP resources."
  type        = string
  default     = "rentalappledger"
}

variable "owner" {
  description = "Owner label applied to all GCP resources."
  type        = string
  default     = "ramprasath"
}

variable "project_id" {
  description = "GCP project ID — injected via TF_VAR_project_id (GitHub Secret: GCP_PROJECT_ID)."
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub organisation name for Workload Identity Federation."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for Workload Identity Federation."
  type        = string
}

# ── Artifact Registry (shared) ────────────────────────────────────────────────

variable "ar_repository_id" {
  description = "Shared Artifact Registry repository ID (from gcp/shared/ outputs)."
  type        = string
}

variable "ar_location" {
  description = "Location of the shared Artifact Registry."
  type        = string
  default     = "us-central1"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "app_subnet_cidr" {
  description = "CIDR block for the application subnet."
  type        = string
}

variable "db_subnet_cidr" {
  description = "CIDR block for the database subnet."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary CIDR range for GKE pods."
  type        = string
}

variable "services_cidr" {
  description = "Secondary CIDR range for GKE services."
  type        = string
}

# ── Compute ───────────────────────────────────────────────────────────────────

variable "cluster_location" {
  description = "GCP zone for the GKE cluster (e.g. us-central1-a)."
  type        = string
}

variable "master_ipv4_cidr" {
  description = "CIDR block for the GKE control-plane private endpoint (/28 required)."
  type        = string
}

variable "master_authorized_cidrs" {
  description = "List of CIDR blocks authorised to reach the GKE API server."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "gke_node_count" {
  description = "Number of nodes in the GKE default node pool."
  type        = number
  default     = 1
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes (e.g. e2-standard-2)."
  type        = string
  default     = "e2-standard-2"
}

variable "gke_disk_size_gb" {
  description = "Boot disk size in GiB for each GKE node."
  type        = number
  default     = 30
}

# ── Database ──────────────────────────────────────────────────────────────────

variable "db_tier" {
  description = "Cloud SQL instance tier (e.g. db-f1-micro, db-g1-small)."
  type        = string
  default     = "db-f1-micro"
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "storage_bucket_location" {
  description = "Multi-region or region for the application GCS bucket (e.g. US, us-central1)."
  type        = string
  default     = "US"
}
