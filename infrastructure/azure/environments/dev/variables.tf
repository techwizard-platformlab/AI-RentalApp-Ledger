# =============================================================================
# Variable sources:
#   terraform.tfvars              → environment, location, db_engine, db sizing
#   GitHub Secret → TF_VAR_*     → env_resource_group_name, shared_resource_group_name,
#                                   subscription_id, acr_name, github_actions_principal_id
# =============================================================================

variable "environment" {
  description = "Deployment environment — set in terraform.tfvars"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "uat", "prod"], var.environment)
    error_message = "Must be one of: dev, qa, uat, prod."
  }
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "env_resource_group_name" {
  description = "Env-specific resource group (e.g. my-Rental-App-Dev). Terraform owns this — safe to destroy."
  type        = string
}

variable "shared_resource_group_name" {
  description = "Permanent shared resource group containing ACR — never destroyed."
  type        = string
}

variable "subscription_id" {
  type      = string
  sensitive = true
}

variable "acr_name" {
  description = "Shared ACR name (from infrastructure/azure/shared/ outputs) — injected via TF_VAR_acr_name"
  type        = string
}

variable "github_actions_principal_id" {
  description = "Object ID of the GitHub Actions OIDC SP — grants Key Vault Secrets Officer."
  type        = string
  sensitive   = true
}

variable "alert_emails" {
  type    = list(string)
  default = []
}

# ── Database engine selection ─────────────────────────────────────────────────
variable "db_engine" {
  type    = string
  default = "postgresql"
  validation {
    condition     = contains(["postgresql", "mssql"], var.db_engine)
    error_message = "db_engine must be 'postgresql' or 'mssql'."
  }
}

variable "postgresql_sku" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "postgresql_storage_mb" {
  type    = number
  default = 32768
}

variable "postgresql_storage_tier" {
  type    = string
  default = "P4"
}

variable "mssql_sku" {
  type    = string
  default = "Basic"
}

variable "mssql_max_size_gb" {
  type    = number
  default = 2
}
