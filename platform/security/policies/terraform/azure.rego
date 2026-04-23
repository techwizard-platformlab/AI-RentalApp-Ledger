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

# ─────────────────────────────────────────────────────────────────────────────
# Rule 5: Deny Public IPs on VMs (Security Hardening)
# ─────────────────────────────────────────────────────────────────────────────
deny contains msg if {
  r := resources[_]
  r.type == "azurerm_public_ip"
  # Optional: allow list for specific edge components if needed
  msg := sprintf("Public IP resource '%s' is prohibited. Use a Load Balancer or Application Gateway.", [r.address])
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 6: Deny wide-open NSG rules (0.0.0.0/0)
# ─────────────────────────────────────────────────────────────────────────────
deny contains msg if {
  r := resources[_]
  r.type == "azurerm_network_security_rule"
  r.change.after.access == "Allow"
  r.change.after.direction == "Inbound"
  r.change.after.source_address_prefix == "*"
  msg := sprintf("NSG Rule '%s' allows inbound traffic from '*'. Use specific CIDR blocks.", [r.address])
}

deny contains msg if {
  r := resources[_]
  r.type == "azurerm_network_security_rule"
  r.change.after.access == "Allow"
  r.change.after.direction == "Inbound"
  r.change.after.source_address_prefix == "0.0.0.0/0"
  msg := sprintf("NSG Rule '%s' allows inbound traffic from '0.0.0.0/0'. Use specific CIDR blocks.", [r.address])
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 7: Enforce encryption at rest for Storage
# ─────────────────────────────────────────────────────────────────────────────
deny contains msg if {
  r := resources[_]
  r.type == "azurerm_storage_account"
  # In modern Azure this is default, but good to enforce/verify
  not r.change.after.infrastructure_encryption_enabled == true
  msg := sprintf("Storage Account '%s' should have infrastructure_encryption_enabled = true for double encryption.", [r.address])
}
