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
  description = "Set after AKS is created; controls AcrPull role assignment"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
