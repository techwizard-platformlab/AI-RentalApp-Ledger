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
  type    = string
  default = "1.29"
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
