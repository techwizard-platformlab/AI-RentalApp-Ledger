# =============================================================================
# Shared infrastructure variables
# Variable sources:
#   terraform.tfvars              → location, location_short, project, acr_sku
#   GitHub Secret → TF_VAR_*     → subscription_id, shared_resource_group_name,
#                                   github_actions_principal_id
# =============================================================================

variable "subscription_id" {
  description = "Azure Subscription ID — injected via TF_VAR_subscription_id"
  type        = string
  sensitive   = true
}

variable "shared_resource_group_name" {
  description = "Permanent resource group for shared resources (ACR). Never destroyed."
  type        = string
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "location_short" {
  type    = string
  default = "eus"
}

variable "project" {
  type    = string
  default = "rentalAppLedger"
}

variable "acr_sku" {
  type    = string
  default = "Basic"
}

variable "github_actions_principal_id" {
  description = "Object ID of the GitHub Actions OIDC SP — grants AcrPush on the shared ACR."
  type        = string
  sensitive   = true
}
