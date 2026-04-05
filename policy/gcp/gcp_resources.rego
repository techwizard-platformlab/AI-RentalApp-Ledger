package gcp

import future.keywords.in
import future.keywords.if

# ─────────────────────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────────────────────
approved_node_types := {"e2-standard-2", "n2-standard-2"}
max_node_count      := 3

# ─────────────────────────────────────────────────────────────────────────────
# Helper
# ─────────────────────────────────────────────────────────────────────────────
resources[r] {
  r := input.resource_changes[_]
  r.change.actions[_] in ["create", "update"]
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny GKE node count > 3 (KodeKloud CPU quota: 7 vCPUs)
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  r.type == "google_container_node_pool"
  count := r.change.after.node_count
  count > max_node_count
  msg := sprintf(
    "[QUOTA] GKE node pool '%s' requests %d nodes. KodeKloud CPU quota max: %d nodes.",
    [r.address, count, max_node_count]
  )
}

deny[msg] {
  r := resources[_]
  r.type == "google_container_cluster"
  count := r.change.after.initial_node_count
  count > max_node_count
  msg := sprintf(
    "[QUOTA] GKE cluster '%s' initial_node_count=%d exceeds max %d.",
    [r.address, count, max_node_count]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny GKE Autopilot (blocked in KodeKloud playground)
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  r.type == "google_container_cluster"
  r.change.after.enable_autopilot == true
  msg := sprintf(
    "[PLAYGROUND] GKE cluster '%s' has enable_autopilot=true. Autopilot is not available in KodeKloud.",
    [r.address]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny GKE node type not in approved list
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  r.type == "google_container_node_pool"
  machine_type := r.change.after.node_config[0].machine_type
  not machine_type in approved_node_types
  msg := sprintf(
    "[COST] GKE node pool '%s' uses machine type '%s'. Approved: %v",
    [r.address, machine_type, approved_node_types]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny Artifact Registry without cleanup policy
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  r.type == "google_artifact_registry_repository"
  cleanup := object.get(r.change.after, "cleanup_policies", [])
  count(cleanup) == 0
  msg := sprintf(
    "[COST] Artifact Registry '%s' has no cleanup policy. Old images will accumulate costs.",
    [r.address]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny GCS bucket without versioning enabled
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  r.type == "google_storage_bucket"
  versioning := object.get(r.change.after, "versioning", [])
  count(versioning) == 0
  msg := sprintf(
    "[SECURITY] GCS bucket '%s' is missing versioning configuration.",
    [r.address]
  )
}

deny[msg] {
  r := resources[_]
  r.type == "google_storage_bucket"
  versioning := r.change.after.versioning[0]
  versioning.enabled != true
  msg := sprintf(
    "[SECURITY] GCS bucket '%s' has versioning disabled.",
    [r.address]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny resources outside US regions
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  location := object.get(r.change.after, "location", "")
  location != ""
  not startswith(location, "us-")
  not startswith(location, "US")
  msg := sprintf(
    "[REGION] Resource '%s' (type: %s) is in region '%s'. Only US regions allowed.",
    [r.address, r.type, location]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny service account with primitive roles (owner/editor at project level)
# ─────────────────────────────────────────────────────────────────────────────
primitive_roles := {"roles/owner", "roles/editor"}

deny[msg] {
  r := resources[_]
  r.type == "google_project_iam_binding"
  r.change.after.role in primitive_roles
  msg := sprintf(
    "[SECURITY] IAM binding '%s' uses primitive role '%s'. Use predefined or custom roles instead.",
    [r.address, r.change.after.role]
  )
}

deny[msg] {
  r := resources[_]
  r.type == "google_project_iam_member"
  r.change.after.role in primitive_roles
  msg := sprintf(
    "[SECURITY] IAM member binding '%s' grants primitive role '%s'. This violates least-privilege.",
    [r.address, r.change.after.role]
  )
}
