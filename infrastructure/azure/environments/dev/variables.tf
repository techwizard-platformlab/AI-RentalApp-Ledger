# =============================================================================
# Variable sources:
#   terraform.tfvars              → environment, location, db_engine, db sizing
#   GitHub Secret → TF_VAR_*     → env_resource_group_name, shared_resource_group_name,
#                                   subscription_id, acr_name, key_vault_name
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
  description = "Azure region for env resources"
  type        = string
  default     = "eastus"
}

variable "env_resource_group_name" {
  description = "Env-specific resource group (e.g. my-Rental-App-Dev). Terraform owns this — safe to destroy."
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
  description = "Shared ACR name (from infrastructure/azure/shared/ outputs) — injected via TF_VAR_acr_name"
  type        = string
}

variable "key_vault_name" {
  description = "Shared Key Vault name (from infrastructure/azure/shared/ outputs) — injected via TF_VAR_key_vault_name"
  type        = string
}

variable "alert_emails" {
  description = "Email addresses for weekly budget alerts"
  type        = list(string)
  default     = []
}

# ── Database engine selection ─────────────────────────────────────────────────
variable "db_engine" {
  description = "Database backend to deploy: 'postgresql' (default) or 'mssql'"
  type        = string
  default     = "postgresql"
  validation {
    condition     = contains(["postgresql", "mssql"], var.db_engine)
    error_message = "db_engine must be 'postgresql' or 'mssql'."
  }
}

# ── PostgreSQL Flexible Server sizing (used when db_engine = "postgresql") ────
variable "postgresql_sku" {
  description = "PostgreSQL Flexible Server SKU (e.g. B_Standard_B1ms, B_Standard_B2ms)"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgresql_storage_mb" {
  description = "PostgreSQL storage in MB (minimum 32768 = 32 GiB)"
  type        = number
  default     = 32768
}

variable "postgresql_storage_tier" {
  description = "PostgreSQL storage tier (P4 for Burstable, P6 for General Purpose)"
  type        = string
  default     = "P4"
}

# ── Azure SQL Database sizing (used when db_engine = "mssql") ────────────────
variable "mssql_sku" {
  description = "Azure SQL Database SKU (Basic, S0, S1, S2)"
  type        = string
  default     = "Basic"
}

variable "mssql_max_size_gb" {
  description = "Azure SQL max database size in GB"
  type        = number
  default     = 2
}
