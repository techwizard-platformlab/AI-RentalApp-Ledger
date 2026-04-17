# =============================================================================
# Variable sources:
#   terraform.tfvars (committed)  → environment, region, github_org, github_repo,
#                                   ar_repository_id, ar_location
#   GitHub Secret → TF_VAR_*     → project_id
# =============================================================================

variable "environment" {
  description = "Set in terraform.tfvars"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "uat", "prod"], var.environment)
    error_message = "Must be one of: dev, qa, uat, prod."
  }
}

variable "region" {
  description = "Set in terraform.tfvars — US-based only"
  type        = string
}

variable "project_id" {
  description = "SECRET — injected via TF_VAR_project_id (GitHub Secret: GCP_PROJECT_ID)"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "Set in terraform.tfvars"
  type        = string
}

variable "github_repo" {
  description = "Set in terraform.tfvars"
  type        = string
}

variable "ar_repository_id" {
  description = "Shared Artifact Registry repository ID (from gcp/shared/ outputs)"
  type        = string
}

variable "ar_location" {
  description = "Location of the shared Artifact Registry"
  type        = string
  default     = "us-central1"
}
