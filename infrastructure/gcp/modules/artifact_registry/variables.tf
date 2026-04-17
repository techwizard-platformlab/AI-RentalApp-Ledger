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

variable "labels" {
  type    = map(string)
  default = {}
}
