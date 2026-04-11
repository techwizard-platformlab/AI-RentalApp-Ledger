# =============================================================================
# Shared Azure infrastructure — applied ONCE, rarely changed.
# Lives in my-Rental-App (permanent RG, never destroyed by env Terraform).
#
# Contains:
#   ACR        — single shared registry; images promoted dev → qa by tag
#   Key Vault  — shared secrets store for all environments
#
# Apply:
#   cd infrastructure/azure/shared
#   terraform init -backend-config=...
#   terraform apply
#
# Env Terraform (dev/qa) references these via data sources — never manages them.
# =============================================================================

locals {
  tags = {
    project = var.project
    tier    = "shared"
    managed = "terraform"
  }
}

# ── ACR — shared container registry ──────────────────────────────────────────
# Single registry for all environments. Tags separate dev/qa images.
# Name must be globally unique, alphanumeric only, 5–50 chars.
resource "random_string" "acr_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_container_registry" "shared" {
  name                = "rental${var.location_short}acr${random_string.acr_suffix.result}"
  location            = var.location
  resource_group_name = var.shared_resource_group_name
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = local.tags
}

# ── Key Vault — shared secrets for all environments ───────────────────────────
# Secrets are namespaced by environment prefix: dev-db-host, qa-db-host, etc.
# RBAC mode — access granted via role assignments on the managed identity.
data "azurerm_client_config" "current" {}

resource "random_string" "kv_suffix" {
  length  = 4
  upper   = false
  special = false
}

resource "azurerm_key_vault" "shared" {
  name                       = "rental-shared-kv-${random_string.kv_suffix.result}"
  location                   = var.location
  resource_group_name        = var.shared_resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  rbac_authorization_enabled = true
  tags                       = local.tags
}

# ── Key Vault role assignments ────────────────────────────────────────────────
# Key Vault Secrets Officer: read + write secrets.
# Assigned to the GitHub Actions OIDC service principal so bootstrap workflows
# (argocd-bootstrap, etc.) can auto-generate and store secrets (e.g. Grafana
# admin password) without manual intervention.
resource "azurerm_role_assignment" "github_actions_kv_secrets_officer" {
  scope                = azurerm_key_vault.shared.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.github_actions_principal_id
}

# Key Vault Secrets User: read-only access for application workloads (AKS pods).
# Assigned to the AKS kubelet managed identity so pods can read secrets directly
# from Key Vault via CSI driver or workload identity (future use).
# principal_id resolved at apply time via data source — requires aks_name var.
data "azurerm_kubernetes_cluster" "dev" {
  count               = var.aks_name != "" ? 1 : 0
  name                = var.aks_name
  resource_group_name = var.aks_resource_group_name
}

resource "azurerm_role_assignment" "aks_kv_secrets_user" {
  count                = var.aks_name != "" ? 1 : 0
  scope                = azurerm_key_vault.shared.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_kubernetes_cluster.dev[0].kubelet_identity[0].object_id
}
