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
  default = "Basic"
}

variable "aks_kubelet_identity_object_id" {
  description = "AKS kubelet identity object ID for AcrPull role assignment"
  type        = string
  default     = ""
}

variable "enable_aks_pull_role" {
  description = "Set to true only after AKS is created. Must be a static bool (not computed) to avoid plan-time errors."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
