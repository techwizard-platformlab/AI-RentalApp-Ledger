variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "region_short" {
  type = string
}

variable "app_subnet_cidr" {
  type    = string
  default = "10.1.1.0/24"
}

variable "db_subnet_cidr" {
  type    = string
  default = "10.1.2.0/24"
}

variable "pods_cidr" {
  description = "GKE pod secondary range"
  type        = string
  default     = "10.2.0.0/16"
}

variable "services_cidr" {
  description = "GKE service secondary range"
  type        = string
  default     = "10.3.0.0/20"
}
