# ACR — Basic SKU is ~$0.167/day (cheapest). Standard adds geo-replication (not needed for learning).
resource "azurerm_container_registry" "this" {
  name                = "${var.environment}${var.location_short}acr" # ACR name: alphanumeric only, 5-50 chars
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku           # Basic | Standard | Premium
  admin_enabled       = false             # Use managed identity / OIDC instead of admin password

  tags = var.tags
}

# Grant AKS kubelet identity pull access to ACR (AcrPull role)
resource "azurerm_role_assignment" "aks_acr_pull" {
  count = var.enable_aks_pull_role ? 1 : 0

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = var.aks_kubelet_identity_object_id
}
