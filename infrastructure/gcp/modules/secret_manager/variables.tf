variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "gke_service_account" {
  type    = string
  default = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "secret_names" {
  description = "List of secret names to create (will be prefixed with environment)"
  type        = list(string)
  default     = ["db-password", "acr-token", "discord-webhook"]
}
