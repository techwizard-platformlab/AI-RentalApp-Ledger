package shared

import future.keywords.in
import future.keywords.if

# ─────────────────────────────────────────────────────────────────────────────
# Helper
# ─────────────────────────────────────────────────────────────────────────────
all_resources[r] {
  r := input.resource_changes[_]
  r.change.actions[_] in ["create", "update"]
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny any resource tagged environment=prod (playground safety guard)
# Prevents accidentally applying prod config in KodeKloud environment.
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := all_resources[_]
  tags := object.get(r.change.after, "tags", {})
  lower(object.get(tags, "env", "")) == "prod"
  msg := sprintf(
    "[SAFETY] Resource '%s' is tagged env=prod. Playground safety guard: prod resources are not allowed in this environment.",
    [r.address]
  )
}

# GCP labels equivalent
deny[msg] {
  r := all_resources[_]
  labels := object.get(r.change.after, "labels", {})
  lower(object.get(labels, "env", "")) == "prod"
  msg := sprintf(
    "[SAFETY] Resource '%s' is labeled env=prod. Playground safety guard: prod resources are not allowed.",
    [r.address]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny more than 3 public IP addresses across all resources
# ─────────────────────────────────────────────────────────────────────────────
public_ip_resources[r] {
  r := all_resources[_]
  r.type in {
    "azurerm_public_ip",
    "google_compute_address",
    "google_compute_global_address"
  }
}

deny[msg] {
  count(public_ip_resources) > 3
  addresses := [r.address | r := public_ip_resources[_]]
  msg := sprintf(
    "[COST] Plan creates %d public IP addresses (%v). Maximum allowed: 3 to control costs.",
    [count(public_ip_resources), addresses]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Warn if no encryption at rest configured (non-blocking)
# ─────────────────────────────────────────────────────────────────────────────

# Azure storage without encryption (default is on, but warn if explicitly disabled)
warn[msg] {
  r := all_resources[_]
  r.type == "azurerm_storage_account"
  queue_enc := object.get(r.change.after, "queue_encryption_key_type", "Service")
  queue_enc == "Service"
  msg := sprintf(
    "[WARN] Storage account '%s': using service-managed encryption. Consider customer-managed keys for production.",
    [r.address]
  )
}

# GCS bucket without CMEK
warn[msg] {
  r := all_resources[_]
  r.type == "google_storage_bucket"
  enc := object.get(r.change.after, "encryption", [])
  count(enc) == 0
  msg := sprintf(
    "[WARN] GCS bucket '%s': no customer-managed encryption key (CMEK) configured.",
    [r.address]
  )
}
