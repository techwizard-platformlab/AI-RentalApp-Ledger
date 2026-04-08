data "azurerm_client_config" "current" {}

# Key Vault — standard SKU.
# KodeKloud NOTE: The permission model (RBAC vs access policy) CANNOT be changed
# once the Key Vault is created — the platform blocks it with InsufficientPermissions.
# The existing dev-eus-kv was created with rbac_authorization_enabled=true (RBAC mode).
# We keep rbac_authorization_enabled=true to match the existing resource and avoid a
# 400 error. Access policies are therefore not available; secrets must be written
# by the Terraform SP which is granted Key Vault Secrets Officer via the KodeKloud
# pre-assigned role, or manually via Azure Portal / az CLI.
resource "azurerm_key_vault" "this" {
  name                       = "${var.environment}-${var.location_short}-kv"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.sku
  soft_delete_retention_days = var.soft_delete_days
  purge_protection_enabled   = false

  # Keep RBAC mode — matches existing cluster; cannot be toggled after creation.
  rbac_authorization_enabled = true

  tags = var.tags

  lifecycle {
    # Prevent Terraform from toggling permission model — causes 400 InsufficientPermissions
    ignore_changes = [rbac_authorization_enabled]
  }
}

# NOTE: azurerm_key_vault_access_policy resources are NOT used here because:
# 1. The Key Vault is in RBAC mode (access policies require non-RBAC mode)
# 2. KodeKloud blocks Microsoft.Authorization/roleAssignments
# Secrets are written by the CI/CD SP directly via az keyvault secret set
# (works if the SP has Key Vault Secrets Officer role in the KodeKloud pre-assignment).
