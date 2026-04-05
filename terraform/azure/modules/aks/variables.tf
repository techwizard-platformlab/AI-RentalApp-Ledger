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

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Set to null to use latest supported version automatically."
  type        = string
  default     = null
}

variable "node_count" {
  type    = number
  default = 1
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "os_disk_size_gb" {
  type    = number
  default = 30
}

variable "subnet_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
