# VPC — custom mode prevents auto-subnet sprawl across all regions (cost + security)
resource "google_compute_network" "this" {
  name                    = "${var.environment}-${var.region_short}-vpc"
  auto_create_subnetworks = false  # custom mode: only create subnets we define
  project                 = var.project_id
}

# App subnet — GKE nodes live here
resource "google_compute_subnetwork" "app" {
  name                     = "${var.environment}-${var.region_short}-app-snet"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.app_subnet_cidr
  project                  = var.project_id
  private_ip_google_access = true  # allow nodes to reach Google APIs without external IP

  # Secondary ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# DB subnet — for future Cloud SQL / stateful workloads
resource "google_compute_subnetwork" "db" {
  name                     = "${var.environment}-${var.region_short}-db-snet"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.db_subnet_cidr
  project                  = var.project_id
  private_ip_google_access = true
}

# Cloud Router — required for Cloud NAT
# Cost note: Cloud Router is free; Cloud NAT charges ~$0.045/hr + data processing
resource "google_compute_router" "this" {
  name    = "${var.environment}-${var.region_short}-router"
  region  = var.region
  network = google_compute_network.this.id
  project = var.project_id
}

# Cloud NAT — lets private GKE nodes pull images without external IPs
resource "google_compute_router_nat" "this" {
  name                               = "${var.environment}-${var.region_short}-nat"
  router                             = google_compute_router.this.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"          # no reserved IPs (cost saving)
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.app.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"  # log only errors to keep Logging costs low
  }
}

# Firewall: allow internal VPC traffic
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.environment}-allow-internal"
  network = google_compute_network.this.name
  project = var.project_id

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.app_subnet_cidr, var.db_subnet_cidr]
}

# Firewall: allow HTTPS inbound from internet
resource "google_compute_firewall" "allow_https" {
  name    = "${var.environment}-allow-https-inbound"
  network = google_compute_network.this.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "https-server"]
}
