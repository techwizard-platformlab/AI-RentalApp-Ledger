data "azurerm_client_config" "current" {}

# Key Vault — standard SKU (~$0.03/10k operations). Premium adds HSM; not needed for learning.
resource "azurerm_key_vault" "this" {
  name                        = "${var.environment}-${var.location_short}-kv"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.sku                    # standard (no HSM)
  soft_delete_retention_days  = var.soft_delete_days       # 7 days minimum — reduces accidental lock-in
  purge_protection_enabled    = false                      # false for dev; enable for prod
  rbac_authorization_enabled  = true                       # RBAC over legacy access policies (best practice)
  tags                        = var.tags
}

# Grant the current Terraform caller Key Vault Administrator (needed for CI/CD to write secrets)
resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant AKS managed identity Key Vault Secrets User (read-only)
resource "azurerm_role_assignment" "aks_kv_secrets_user" {
  count = var.enable_aks_kv_role ? 1 : 0

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.aks_principal_id
}
