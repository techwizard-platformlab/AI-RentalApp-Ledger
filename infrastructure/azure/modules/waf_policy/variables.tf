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

variable "waf_mode" {
  description = "Detection (dev) or Prevention (qa/uat/prod)"
  type        = string
  default     = "Detection"
}

variable "tags" {
  type    = map(string)
  default = {}
}
