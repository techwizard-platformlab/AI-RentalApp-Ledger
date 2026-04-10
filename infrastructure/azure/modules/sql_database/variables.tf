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
  description = "Azure SQL Database SKU (Basic | S0 | S1 | S2 | S3 | S4)"
  type        = string
  default     = "Basic"
  validation {
    condition     = contains(["Basic", "S0", "S1", "S2", "S3", "S4"], var.db_sku)
    error_message = "Allowed SKUs: Basic, S0, S1, S2, S3, S4."
  }
}

variable "max_size_gb" {
  description = "Maximum database size in GB — cost constraint: keep disk size low"
  type        = number
  default     = 2
  validation {
    condition     = var.max_size_gb <= 50
    error_message = "Maximum database size is 50 GB (cost constraint)."
  }
}

variable "aks_subnet_cidr" {
  description = "AKS subnet CIDR — used to open SQL Server firewall for pod traffic"
  type        = string
}

variable "key_vault_name" {
  description = "Name of the Key Vault where DB secrets are stored. Null when shared layer has not yet run — secrets are written on the next apply once Key Vault exists."
  type        = string
  default     = null
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
