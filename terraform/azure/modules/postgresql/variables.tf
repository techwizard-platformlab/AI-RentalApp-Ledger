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
