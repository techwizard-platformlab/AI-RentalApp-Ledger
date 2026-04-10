# =============================================================================
# Shared infrastructure variables
# These resources live in the permanent RG and are never destroyed.
#
# Variable sources:
#   terraform.tfvars              → location, project
#   GitHub Secret → TF_VAR_*     → subscription_id, shared_resource_group_name
# =============================================================================

variable "subscription_id" {
  description = "Azure Subscription ID — injected via TF_VAR_subscription_id"
  type        = string
  sensitive   = true
}

variable "shared_resource_group_name" {
  description = "Permanent resource group for shared resources (ACR, Key Vault, state storage). Never destroyed."
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "location_short" {
  description = "Short region code used in resource names"
  type        = string
  default     = "eus"
}

variable "project" {
  description = "Project name used in resource tags"
  type        = string
  default     = "rentalAppLedger"
}

variable "acr_sku" {
  description = "ACR SKU — Basic for cost savings, Standard for geo-replication"
  type        = string
  default     = "Basic"
}

variable "alert_emails" {
  description = "Email addresses for budget alerts"
  type        = list(string)
  default     = []
}
