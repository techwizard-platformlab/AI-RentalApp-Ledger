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

variable "address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "subnets" {
  description = "Map of subnet key to CIDR block — created inline to avoid API propagation race"
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
