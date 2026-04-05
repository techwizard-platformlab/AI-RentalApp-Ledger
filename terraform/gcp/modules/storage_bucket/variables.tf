variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "suffix" {
  type    = string
  default = "tfstate"
}

variable "location" {
  description = "US multi-region for durability"
  type        = string
  default     = "US"
}

variable "labels" {
  type    = map(string)
  default = {}
}
