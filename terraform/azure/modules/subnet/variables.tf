variable "environment" {
  type = string
}

variable "location_short" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "vnet_name" {
  type = string
}

variable "subnets" {
  description = "Map of subnet name to CIDR block"
  type        = map(string)
}
