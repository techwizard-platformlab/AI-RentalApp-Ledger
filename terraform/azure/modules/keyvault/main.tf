data "azurerm_client_config" "current" {}

# Key Vault — standard SKU, access-policy mode (NOT RBAC).
# KodeKloud blocks Microsoft.Authorization/roleAssignments, so RBAC-based
# Key Vault access (rbac_authorization_enabled = true) cannot be used.
# Access policies are Key Vault–native and do NOT require role assignments.
resource "azurerm_key_vault" "this" {
  name                       = "${var.environment}-${var.location_short}-kv"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.sku
  soft_delete_retention_days = var.soft_delete_days
  purge_protection_enabled   = false

  # Use classic access policies — avoids role assignment dependency
  rbac_authorization_enabled = false

  tags = var.tags
}

# ── Access policy: Terraform service principal ─────────────────────────────────
# Grants full secret CRUD so Terraform can write DB credentials and app secrets.
resource "azurerm_key_vault_access_policy" "terraform_sp" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
}

# ── Access policy: CI/CD service principal (bootstrap workflow reads secrets) ──
# Same SP used for Azure login in GitHub Actions — needs Get + List only.
resource "azurerm_key_vault_access_policy" "cicd_sp" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = var.cicd_sp_object_id

  secret_permissions = ["Get", "List"]
}
