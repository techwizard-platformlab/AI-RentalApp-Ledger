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

# ── RBAC — role assignments ───────────────────────────────────────────────────
variable "github_actions_principal_id" {
  description = <<-EOT
    Object ID (OID) of the GitHub Actions OIDC service principal / managed identity.
    Used to grant Key Vault Secrets Officer so CI/CD workflows can write secrets.
    Find it: az ad sp show --id <AZURE_CLIENT_ID> --query id -o tsv
  EOT
  type        = string
  # Default from current infrastructure — update if the service principal changes.
  default     = "203e0ec4-f4e5-4397-834a-0490cc424549"
}

variable "aks_name" {
  description = "AKS cluster name — used to look up kubelet identity for KV Secrets User assignment. Set to '' to skip."
  type        = string
  default     = "dev-eus2-aks"
}

variable "aks_resource_group_name" {
  description = "Resource group containing the AKS cluster referenced by aks_name."
  type        = string
  default     = "my-Rental-App-Dev"
}

