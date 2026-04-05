# GKE Standard mode — Autopilot is blocked in KodeKloud playground
# Cost note: Standard GKE cluster management fee ~$0.10/hr; Autopilot is per-pod.
# Single node (e2-standard-2) keeps within KodeKloud 7 vCPU quota.
resource "google_container_cluster" "this" {
  name     = "${var.environment}-${var.region_short}-gke"
  location = var.region   # regional cluster for HA; use zone for single-node dev cost saving
  project  = var.project_id

  # Remove default node pool so we can define our own with granular settings
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network_name
  subnetwork = var.subnet_name

  # IP aliasing required for VPC-native private cluster
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Private cluster — nodes have no public IPs (more secure, uses Cloud NAT for egress)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false  # keep master endpoint public for kubectl access during learning
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  # Restrict kubectl access to known CIDRs
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Workload Identity — lets pods authenticate to GCP APIs without SA key files
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable RBAC (required for workload identity)
  enable_legacy_abac = false

  # Disable costly add-ons not needed for learning
  addons_config {
    http_load_balancing {
      disabled = false  # keep for ingress
    }
    horizontal_pod_autoscaling {
      disabled = true  # disable to avoid unexpected node scale-out
    }
    network_policy_config {
      disabled = false
    }
  }

  # Network policy (Calico) for pod-level isolation
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  release_channel {
    channel = "REGULAR"  # REGULAR = stable updates; RAPID = bleeding edge
  }

  resource_labels = var.labels
}

# Custom node pool (replaces default)
# Cost note: e2-standard-2 = 2 vCPU / 8 GB. Preemptible would be cheaper but
# unsuitable for stateful apps; use spot for dev if cost is critical.
resource "google_container_node_pool" "primary" {
  name       = "${var.environment}-${var.region_short}-nodepool"
  cluster    = google_container_cluster.this.name
  location   = var.region
  project    = var.project_id
  node_count = var.node_count  # 1 in dev to stay within KodeKloud 7 vCPU quota

  node_config {
    machine_type = var.machine_type   # e2-standard-2 (KodeKloud E2/N2 series only)
    disk_size_gb = var.disk_size_gb   # max 50 GB per KodeKloud disk limit
    disk_type    = "pd-standard"      # standard persistent disk — cheapest option

    # Use Workload Identity on nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Minimal OAuth scopes — principle of least privilege
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = var.labels
    tags   = ["gke-node", "${var.environment}-gke"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Service account for GKE nodes (least-privilege — no Editor role)
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.environment}-gke-nodes-sa"
  display_name = "GKE Nodes SA — ${var.environment}"
  project      = var.project_id
}

# Minimal roles for GKE nodes
resource "google_project_iam_member" "gke_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}
