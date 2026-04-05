package terraform.gcp

import future.keywords.in
import future.keywords.if

# ─────────────────────────────────────────────────────────────────────────────
# Data references
# ─────────────────────────────────────────────────────────────────────────────
allowed_regions := data.approved_skus.gcp.allowed_regions
max_node_count  := data.approved_skus.gcp.max_node_count   # 3

# ─────────────────────────────────────────────────────────────────────────────
# Helper: collect all resources from terraform plan JSON
# ─────────────────────────────────────────────────────────────────────────────
resources := {r |
  r := input.resource_changes[_]
  r.change.actions[_] in ["create", "update"]
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 1: Deny GKE node pool with count > 3 (KodeKloud quota)
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] if {
  r := resources[_]
  r.type == "google_container_node_pool"
  count := r.change.after.node_count
  count > max_node_count
  msg := sprintf(
    "GKE node pool '%s' requests %d nodes. KodeKloud quota max: %d",
    [r.address, count, max_node_count]
  )
}

# Also check initial_node_count on the cluster itself
deny[msg] if {
  r := resources[_]
  r.type == "google_container_cluster"
  count := r.change.after.initial_node_count
  count > max_node_count
  msg := sprintf(
    "GKE cluster '%s' requests initial_node_count=%d. KodeKloud quota max: %d",
    [r.address, count, max_node_count]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 2: Deny GKE Autopilot (not available in KodeKloud playground)
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] if {
  r := resources[_]
  r.type == "google_container_cluster"
  r.change.after.enable_autopilot == true
  msg := sprintf(
    "GKE cluster '%s' has enable_autopilot=true. Autopilot is not available in the KodeKloud playground.",
    [r.address]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 3: Deny resources outside US regions
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] if {
  r := resources[_]
  location := r.change.after.location
  not startswith(location, "us-")
  msg := sprintf(
    "Resource '%s' (type: %s) is in region '%s'. Only US regions are allowed (us-*).",
    [r.address, r.type, location]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 4: Deny storage bucket without versioning enabled
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] if {
  r := resources[_]
  r.type == "google_storage_bucket"
  versioning := r.change.after.versioning
  count(versioning) == 0
  msg := sprintf(
    "GCS bucket '%s' does not have versioning configured.",
    [r.address]
  )
}

deny[msg] if {
  r := resources[_]
  r.type == "google_storage_bucket"
  versioning := r.change.after.versioning[0]
  versioning.enabled != true
  msg := sprintf(
    "GCS bucket '%s' has versioning disabled. Set versioning[0].enabled = true.",
    [r.address]
  )
}
