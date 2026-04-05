# =============================================================================
# Variable sources:
#   terraform.tfvars (committed)  → environment, region, github_org, github_repo
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
  description = "Set in terraform.tfvars — US-based only (KodeKloud constraint)"
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
