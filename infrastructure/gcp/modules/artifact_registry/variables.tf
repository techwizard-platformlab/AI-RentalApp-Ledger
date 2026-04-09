variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "region_short" {
  type = string
}

variable "location" {
  type    = string
  default = "us-central1"
}

variable "gke_service_account" {
  type    = string
  default = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}
