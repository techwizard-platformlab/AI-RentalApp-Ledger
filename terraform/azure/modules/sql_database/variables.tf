variable "environment" {
  description = "Deployment environment (dev, qa, prod)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "location_short" {
  description = "Short location code used in resource names (e.g. eus)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "sql_admin_username" {
  description = "SQL Server administrator login"
  type        = string
  default     = "rentaladmin"
}

variable "db_sku" {
  description = "Azure SQL Database SKU (KodeKloud: Basic | S0 | S1 | S2 | S3 | S4)"
  type        = string
  default     = "Basic"
  validation {
    condition     = contains(["Basic", "S0", "S1", "S2", "S3", "S4"], var.db_sku)
    error_message = "KodeKloud only allows: Basic, S0, S1, S2, S3, S4."
  }
}

variable "max_size_gb" {
  description = "Maximum database size in GB (KodeKloud max: 50)"
  type        = number
  default     = 2
  validation {
    condition     = var.max_size_gb <= 50
    error_message = "KodeKloud limits maximum database size to 50 GB."
  }
}

variable "aks_subnet_cidr" {
  description = "AKS subnet CIDR — used to open SQL Server firewall for pod traffic"
  type        = string
}

variable "key_vault_name" {
  description = "Name of the Key Vault (used with az CLI local-exec to avoid RBAC role assignment requirement)"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
