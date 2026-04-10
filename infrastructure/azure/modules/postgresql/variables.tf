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

variable "db_admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "rentaladmin"
}

variable "sku_name" {
  description = "PostgreSQL Flexible Server SKU (e.g. B_Standard_B1ms, B_Standard_B2ms, GP_Standard_D2s_v3)"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage size in MB (minimum 32768 = 32 GiB)"
  type        = number
  default     = 32768
}

variable "storage_tier" {
  description = "Storage performance tier (P4 for Burstable, P6 for General Purpose)"
  type        = string
  default     = "P4"
}

variable "aks_subnet_cidr" {
  description = "AKS subnet CIDR block — used to open PostgreSQL firewall for pod traffic"
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Key Vault where secrets will be stored"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
