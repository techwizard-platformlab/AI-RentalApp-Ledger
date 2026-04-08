variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_location" {
  description = "Zone or region for the GKE cluster and node pool. Use a zone (e.g. us-central1-a) for single-node dev/qa to avoid creating 1 node per zone. Use a region for prod HA."
  type        = string
  # No default — must be set explicitly per environment to avoid accidental regional clusters.
}

variable "region_short" {
  type = string
}

variable "network_name" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "master_ipv4_cidr" {
  description = "CIDR block for GKE master (must not overlap with node/pod CIDRs)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_cidrs" {
  description = "List of CIDRs allowed to reach the GKE master API"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    { cidr_block = "0.0.0.0/0", display_name = "all — restrict in prod" }
  ]
}

variable "node_count" {
  type    = number
  default = 1
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "disk_size_gb" {
  type    = number
  default = 30
}

variable "labels" {
  type    = map(string)
  default = {}
}
