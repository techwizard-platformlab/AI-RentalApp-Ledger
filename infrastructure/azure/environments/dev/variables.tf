# =============================================================================
# Variable sources:
#   terraform.tfvars              → environment, location, networking, compute,
#                                   db_engine, db sizing, budget
#   GitHub Secret → TF_VAR_*     → env_resource_group_name, github_actions_principal_id
# =============================================================================

variable "environment" {
  description = "Deployment environment — set in terraform.tfvars."
  type        = string
  validation {
    condition     = contains(["dev", "qa", "uat", "prod"], var.environment)
    error_message = "Must be one of: dev, qa, uat, prod."
  }
}

variable "location" {
  description = "Azure region for all resources in this environment."
  type        = string
  default     = "eastus2"
}

variable "location_short" {
  description = "Short location code used in resource name suffixes (e.g. eus2). Required — set in terraform.tfvars."
  type        = string
}

variable "project" {
  description = "Project name applied to the 'project' resource tag."
  type        = string
  default     = "rentalAppLedger"
}

variable "owner" {
  description = "Owning team applied to the 'owner' resource tag."
  type        = string
  default     = "techwizard-platformlab"
}

variable "env_resource_group_name" {
  description = "Env-specific resource group (e.g. my-Rental-App-Dev). Terraform owns this — safe to destroy."
  type        = string
}

variable "acr_sku" {
  description = "ACR SKU — Basic is sufficient for dev."
  type        = string
  default     = "Basic"
}

variable "github_actions_principal_id" {
  description = "Object ID of the GitHub Actions OIDC service principal — grants Key Vault Secrets Officer."
  type        = string
  sensitive   = true
}

variable "alert_emails" {
  description = "Email addresses to notify when budget thresholds are breached."
  type        = list(string)
  default     = []
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vnet_cidr" {
  description = "Address space for the environment virtual network (e.g. 10.0.0.0/16)."
  type        = string
}

variable "subnet_cidrs" {
  description = "Map of subnet name to CIDR block. Expected keys: aks, ingress, data."
  type        = map(string)
}

# ── Compute ───────────────────────────────────────────────────────────────────

variable "aks_node_count" {
  description = "Number of nodes in the AKS default node pool."
  type        = number
  default     = 1
}

variable "aks_vm_size" {
  description = "VM SKU for the AKS node pool (e.g. Standard_D2s_v3)."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_os_disk_gb" {
  description = "OS disk size in GiB for each AKS node."
  type        = number
  default     = 30
}

variable "kubernetes_version" {
  description = "Kubernetes version to pin the AKS cluster to. Null lets Azure manage upgrades."
  type        = string
  default     = null
}

variable "api_server_authorized_ip_ranges" {
  description = "IP ranges authorized to access the Kubernetes API server."
  type        = list(string)
  default     = ["0.0.0.0/32"] # Default to blocking all; override in tfvars
}

# ── Database engine selection ─────────────────────────────────────────────────

variable "db_engine" {
  description = "Database engine to deploy — exactly one of 'postgresql' or 'mssql'."
  type        = string
  default     = "postgresql"
  validation {
    condition     = contains(["postgresql", "mssql"], var.db_engine)
    error_message = "db_engine must be 'postgresql' or 'mssql'."
  }
}

variable "postgresql_sku" {
  description = "SKU name for the PostgreSQL Flexible Server (e.g. B_Standard_B1ms)."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgresql_storage_mb" {
  description = "Storage allocated to the PostgreSQL server in MiB. Minimum 32768 (32 GiB)."
  type        = number
  default     = 32768
}

variable "postgresql_storage_tier" {
  description = "Performance tier for PostgreSQL storage (e.g. P4)."
  type        = string
  default     = "P4"
}

variable "mssql_sku" {
  description = "SKU name for the Azure SQL Database (e.g. Basic, S1)."
  type        = string
  default     = "Basic"
}

variable "mssql_max_size_gb" {
  description = "Maximum data size in GiB for the Azure SQL Database."
  type        = number
  default     = 2
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "app_storage_containers" {
  description = "List of blob container names to create in the application storage account."
  type        = list(string)
  default     = ["uploads", "backups"]
}

# ── Cost management ───────────────────────────────────────────────────────────

variable "monthly_budget_usd" {
  description = "Monthly spend limit in USD for the environment resource group budget alert."
  type        = number
  default     = 22
}

variable "budget_start_date" {
  description = "ISO 8601 start date for the budget period (e.g. 2026-04-01T00:00:00Z)."
  type        = string
}

# ── GitHub integration ────────────────────────────────────────────────────────

variable "github_token" {
  description = "GitHub PAT with repo scope to push secrets to the app repository."
  type        = string
  sensitive   = true
}

variable "app_github_repo" {
  description = "Name of the application GitHub repository to push secrets to."
  type        = string
  default     = "RentalApp-Build"
}
