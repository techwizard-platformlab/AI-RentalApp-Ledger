# =============================================================================
# Variable sources:
#   terraform.tfvars (committed)  → environment, location
#   GitHub Secret → TF_VAR_*     → resource_group_name
# =============================================================================

variable "environment" {
  description = "Set in terraform.tfvars"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "uat", "prod"], var.environment)
    error_message = "Must be one of: dev, qa, uat, prod."
  }
}

variable "location" {
  description = "Set in terraform.tfvars — KodeKloud allowed regions only"
  type        = string
}

variable "resource_group_name" {
  description = "SECRET — injected via TF_VAR_resource_group_name (GitHub Secret: AZURE_RESOURCE_GROUP)"
  type        = string
  sensitive   = true
}

variable "subscription_id" {
  description = "Azure Subscription ID — injected via TF_VAR_subscription_id"
  type        = string
  sensitive   = true
}
