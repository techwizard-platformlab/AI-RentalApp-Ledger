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

variable "suffix" {
  description = "Appended to storage account name for global uniqueness"
  type        = string
  default     = "app"
}

variable "containers" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
