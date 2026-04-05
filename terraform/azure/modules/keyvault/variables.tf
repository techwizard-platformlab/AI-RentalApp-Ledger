variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "location_short" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "sku" {
  type    = string
  default = "standard"
}

variable "soft_delete_days" {
  type    = number
  default = 7
}

variable "aks_principal_id" {
  type    = string
  default = ""
}

variable "enable_aks_kv_role" {
  description = "Set to true only after AKS is created. Must be a static bool (not computed) to avoid plan-time errors."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
