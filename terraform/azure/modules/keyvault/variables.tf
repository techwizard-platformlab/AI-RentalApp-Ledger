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

variable "tags" {
  type    = map(string)
  default = {}
}
