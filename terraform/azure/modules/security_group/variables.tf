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

variable "subnet_ids" {
  type        = map(string)
  default     = {}
  description = "Map of name to subnet ID to associate with the security group"
}

variable "tags" {
  type    = map(string)
  default = {}
}
