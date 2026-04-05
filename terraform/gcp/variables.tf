# =============================================================================
# Root-level variables — shared across all GCP modules
# Naming convention: {env}-{region-short}-{resource}  e.g. dev-use1-gke
# =============================================================================

variable "project_id" {
  description = "GCP project ID — KodeKloud default project only (cannot create new projects)"
  type        = string
}

variable "region" {
  description = "GCP region — US-based only (KodeKloud constraint)"
  type        = string
  default     = "us-central1"
  validation {
    condition     = startswith(var.region, "us-")
    error_message = "KodeKloud: only US-based regions are allowed."
  }
}

variable "region_short" {
  description = "Short region code for naming (e.g. us-central1 → use1)"
  type        = string
  default     = "use1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, staging, prod."
  }
}

variable "project_name" {
  description = "Project tag value"
  type        = string
  default     = "rentalAppLedger"
}

variable "owner" {
  description = "Owner tag value"
  type        = string
  default     = "ramprasath"
}

variable "common_labels" {
  description = "Labels applied to all resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_subnet_cidr" {
  description = "CIDR for the app subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "db_subnet_cidr" {
  description = "CIDR for the db subnet"
  type        = string
  default     = "10.1.2.0/24"
}

# ---------------------------------------------------------------------------
# GKE
# ---------------------------------------------------------------------------
variable "gke_node_count" {
  description = "Number of nodes in the GKE node pool (1 for dev to respect CPU quota)"
  type        = number
  default     = 1
}

variable "gke_machine_type" {
  description = "GKE node machine type — e2-standard-2 = 2 vCPU / 8 GB, lowest viable for KodeKloud"
  type        = string
  default     = "e2-standard-2"
}

variable "gke_disk_size_gb" {
  description = "Boot disk size per node in GB — max 50 GB (KodeKloud)"
  type        = number
  default     = 30 # keep small; KodeKloud max 50 GB per disk
}

variable "kubernetes_version" {
  description = "GKE Kubernetes version (use RAPID channel default if empty)"
  type        = string
  default     = "latest"
}

# ---------------------------------------------------------------------------
# Artifact Registry
# ---------------------------------------------------------------------------
variable "artifact_registry_location" {
  description = "Artifact Registry location"
  type        = string
  default     = "us-central1"
}

# ---------------------------------------------------------------------------
# GitHub (for workload identity)
# ---------------------------------------------------------------------------
variable "github_org" {
  description = "GitHub organisation or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org prefix)"
  type        = string
}
