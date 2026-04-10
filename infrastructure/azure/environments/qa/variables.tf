variable "environment" {
  description = "Deployment environment — set in terraform.tfvars"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "uat", "prod"], var.environment)
    error_message = "Must be one of: dev, qa, uat, prod."
  }
}

variable "location" {
  description = "Azure region for env resources"
  type        = string
  default     = "eastus"
}

variable "env_resource_group_name" {
  description = "Env-specific resource group (e.g. my-Rental-App-QA). Terraform owns this — safe to destroy."
  type        = string
}

variable "shared_resource_group_name" {
  description = "Permanent shared resource group (e.g. my-Rental-App). Contains ACR, Key Vault — never destroyed."
  type        = string
}

variable "subscription_id" {
  description = "Azure Subscription ID — injected via TF_VAR_subscription_id"
  type        = string
  sensitive   = true
}

variable "acr_name" {
  description = "Shared ACR name — injected via TF_VAR_acr_name"
  type        = string
}

variable "key_vault_name" {
  description = "Shared Key Vault name — injected via TF_VAR_key_vault_name"
  type        = string
}

variable "alert_emails" {
  description = "Email addresses for weekly budget alerts"
  type        = list(string)
  default     = []
}
