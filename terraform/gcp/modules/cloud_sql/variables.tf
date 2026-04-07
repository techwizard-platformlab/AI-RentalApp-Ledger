variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, qa, prod)"
  type        = string
}

variable "region" {
  description = "GCP region (e.g. us-central1)"
  type        = string
}

variable "region_short" {
  description = "Short region code used in resource names (e.g. use1)"
  type        = string
}

variable "vpc_network_id" {
  description = "VPC network self_link for private IP peering"
  type        = string
}

variable "db_tier" {
  description = "Cloud SQL machine tier (db-f1-micro for dev, db-g1-small for qa)"
  type        = string
  default     = "db-f1-micro"
}

variable "gke_service_account" {
  description = "GKE node service account email — granted Secret Manager accessor role"
  type        = string
}

variable "labels" {
  description = "GCP resource labels"
  type        = map(string)
  default     = {}
}
