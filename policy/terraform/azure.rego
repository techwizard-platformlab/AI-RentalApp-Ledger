package terraform.azure

import future.keywords.in
import future.keywords.if
import future.keywords.contains

# ─────────────────────────────────────────────────────────────────────────────
# Data references
# ─────────────────────────────────────────────────────────────────────────────
approved_vm_sizes := data.approved_skus.azure.aks_vm_sizes
allowed_regions   := data.approved_skus.azure.allowed_regions

# ─────────────────────────────────────────────────────────────────────────────
# Helper: collect all resources from terraform plan JSON
# ─────────────────────────────────────────────────────────────────────────────
resources := {r |
  r := input.resource_changes[_]
  r.change.actions[_] in ["create", "update"]
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 1: Deny AKS with unapproved VM size
# ─────────────────────────────────────────────────────────────────────────────
deny contains msg if {
  r := resources[_]
  r.type == "azurerm_kubernetes_cluster"
  vm_size := r.change.after.default_node_pool[0].vm_size
  not vm_size in approved_vm_sizes
  msg := sprintf(
    "AKS cluster '%s' uses VM size '%s'. Approved sizes: %v",
    [r.address, vm_size, approved_vm_sizes]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 2: Deny resources deployed outside allowed regions
# ─────────────────────────────────────────────────────────────────────────────
deny contains msg if {
  r := resources[_]
  location := r.change.after.location
  not location in allowed_regions
  msg := sprintf(
    "Resource '%s' (type: %s) is in region '%s'. Allowed regions: %v",
    [r.address, r.type, location, allowed_regions]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 3: Deny storage accounts without HTTPS-only enabled
# ─────────────────────────────────────────────────────────────────────────────
deny contains msg if {
  r := resources[_]
  r.type == "azurerm_storage_account"
  r.change.after.enable_https_traffic_only != true
  msg := sprintf(
    "Storage account '%s' must have enable_https_traffic_only = true",
    [r.address]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 4: Deny Key Vault with insufficient soft-delete retention
# ─────────────────────────────────────────────────────────────────────────────
deny contains msg if {
  r := resources[_]
  r.type == "azurerm_key_vault"
  retention := r.change.after.soft_delete_retention_days
  retention < 7
  msg := sprintf(
    "Key Vault '%s' has soft_delete_retention_days=%d. Minimum required: 7",
    [r.address, retention]
  )
}
