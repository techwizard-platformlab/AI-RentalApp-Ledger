data "azurerm_client_config" "current" {}

# Key Vault — standard SKU (~$0.03/10k operations)
resource "azurerm_key_vault" "this" {
  name                       = "${var.environment}-${var.location_short}-kv"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.sku
  soft_delete_retention_days = var.soft_delete_days
  purge_protection_enabled   = false
  rbac_authorization_enabled = true

  tags = var.tags
}

# NOTE: Role assignments (Key Vault Administrator, Key Vault Secrets User) are
# intentionally removed — KodeKloud blocks Microsoft.Authorization/roleAssignments
# on this scope. Assign manually via Azure Portal if needed.
