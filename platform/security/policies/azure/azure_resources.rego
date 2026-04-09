package azure

import future.keywords.in
import future.keywords.if

# ─────────────────────────────────────────────────────────────────────────────
# Data: approved values
# ─────────────────────────────────────────────────────────────────────────────
approved_vm_sizes := {"Standard_B2s", "Standard_D2s_v3", "Standard_B1s"}
allowed_regions   := {"eastus", "westus", "centralus", "southcentralus"}
required_tags     := {"env", "project", "owner"}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: all resources being created or updated
# ─────────────────────────────────────────────────────────────────────────────
resources[r] {
  r := input.resource_changes[_]
  r.change.actions[_] in ["create", "update"]
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny AKS nodes > 2 (KodeKloud quota protection)
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  r.type == "azurerm_kubernetes_cluster"
  node_count := r.change.after.default_node_pool[0].node_count
  node_count > 2
  msg := sprintf(
    "[QUOTA] AKS '%s' requests %d nodes. KodeKloud limit is 2 nodes.",
    [r.address, node_count]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny VM sizes not in approved list
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  r.type == "azurerm_kubernetes_cluster"
  vm_size := r.change.after.default_node_pool[0].vm_size
  not vm_size in approved_vm_sizes
  msg := sprintf(
    "[COST] AKS '%s' uses VM size '%s'. Approved: %v",
    [r.address, vm_size, approved_vm_sizes]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny resources in non-US regions
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  location := r.change.after.location
  not location in allowed_regions
  msg := sprintf(
    "[REGION] Resource '%s' (type: %s) is in region '%s'. Allowed: %v",
    [r.address, r.type, location, allowed_regions]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny storage accounts without https_traffic_only_enabled = true
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  r.type == "azurerm_storage_account"
  r.change.after.enable_https_traffic_only != true
  msg := sprintf(
    "[SECURITY] Storage account '%s' must have enable_https_traffic_only = true.",
    [r.address]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny Key Vault without soft_delete_retention_days
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  r.type == "azurerm_key_vault"
  not r.change.after.soft_delete_retention_days
  msg := sprintf(
    "[SECURITY] Key Vault '%s' is missing soft_delete_retention_days. Minimum: 7.",
    [r.address]
  )
}

deny[msg] {
  r := resources[_]
  r.type == "azurerm_key_vault"
  r.change.after.soft_delete_retention_days < 7
  msg := sprintf(
    "[SECURITY] Key Vault '%s' soft_delete_retention_days=%d. Minimum: 7.",
    [r.address, r.change.after.soft_delete_retention_days]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny ACR with SKU = Premium (cost)
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  r.type == "azurerm_container_registry"
  upper(r.change.after.sku) == "PREMIUM"
  msg := sprintf(
    "[COST] ACR '%s' uses Premium SKU. Use Basic or Standard for dev/playground.",
    [r.address]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny any resource missing required tags (env, project, owner)
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := resources[_]
  tags := object.get(r.change.after, "tags", {})
  missing := required_tags - {k | tags[k]}
  count(missing) > 0
  msg := sprintf(
    "[TAGS] Resource '%s' (type: %s) is missing required tags: %v",
    [r.address, r.type, missing]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Warn if AKS node pool > 1 node in dev environment
# ─────────────────────────────────────────────────────────────────────────────
warn[msg] {
  r := resources[_]
  r.type == "azurerm_kubernetes_cluster"
  node_count := r.change.after.default_node_pool[0].node_count
  node_count > 1
  tags := object.get(r.change.after, "tags", {})
  lower(object.get(tags, "env", "")) == "dev"
  msg := sprintf(
    "[WARN] AKS '%s' has %d nodes in dev environment. Consider 1 node to save cost.",
    [r.address, node_count]
  )
}
