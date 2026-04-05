# =============================================================================
# Root-level variables — shared across all modules
# Naming convention: {env}-{region-short}-{resource}  e.g. dev-eus-aks
# =============================================================================

variable "environment" {
  description = "Deployment environment"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, staging, prod."
  }
}

variable "location" {
  description = "Azure region — KodeKloud allowed regions only"
  type        = string
  default     = "eastus"
  validation {
    condition     = contains(["eastus", "westus", "centralus", "southcentralus"], var.location)
    error_message = "KodeKloud: only eastus, westus, centralus, southcentralus are allowed."
  }
}

# Short region code used in resource names (e.g. eastus → eus)
variable "location_short" {
  description = "Short region code for naming (eus | wus | cus | scus)"
  type        = string
  default     = "eus"
}

variable "resource_group_name" {
  description = "Existing Resource Group name — DO NOT create a new one (KodeKloud constraint)"
  type        = string
}

variable "project" {
  description = "Project tag value"
  type        = string
  default     = "rentalAppLedger"
}

variable "owner" {
  description = "Owner tag value"
  type        = string
  default     = "ramprasath"
}

# Common tags applied to all resources
variable "common_tags" {
  description = "Tags merged onto every resource"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vnet_address_space" {
  description = "VNet CIDR block"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_cidrs" {
  description = "Map of subnet name → CIDR"
  type        = map(string)
  default = {
    aks     = "10.0.1.0/24"
    ingress = "10.0.2.0/24"
    data    = "10.0.3.0/24"
  }
}

# ---------------------------------------------------------------------------
# AKS
# ---------------------------------------------------------------------------
variable "aks_node_count" {
  description = "Initial node count (cost-sensitive: keep at 1 for dev)"
  type        = number
  default     = 1
}

variable "aks_vm_size" {
  description = "AKS node VM size — Standard_B2s is lowest cost that fits KodeKloud"
  type        = string
  default     = "Standard_B2s"
}

variable "aks_os_disk_size_gb" {
  description = "AKS node OS disk in GB — max 128 GB (KodeKloud), keep low for cost"
  type        = number
  default     = 30
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.29"
}

# ---------------------------------------------------------------------------
# ACR
# ---------------------------------------------------------------------------
variable "acr_sku" {
  description = "ACR SKU — Basic is cheapest; no geo-replication needed for learning"
  type        = string
  default     = "Basic" # ~$0.167/day; Standard ~$0.667/day
}

# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------
variable "keyvault_sku" {
  description = "Key Vault SKU — standard is sufficient (premium adds HSM, not needed)"
  type        = string
  default     = "standard"
}

variable "keyvault_soft_delete_days" {
  description = "Soft delete retention in days (min 7, max 90)"
  type        = number
  default     = 7 # minimum to reduce accidental lock-in costs
}
