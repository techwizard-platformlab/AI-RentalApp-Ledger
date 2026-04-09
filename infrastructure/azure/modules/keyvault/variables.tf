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

variable "cicd_sp_object_id" {
  description = "Reserved — not used in RBAC mode (SP may lack role assignment permissions — check IAM). Kept for future use."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
