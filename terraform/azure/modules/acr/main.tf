# ACR — Basic SKU is ~$0.167/day (cheapest). Standard adds geo-replication (not needed for learning).
# Name must be globally unique, alphanumeric only, 5-50 chars — use random suffix
resource "random_string" "acr_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_container_registry" "this" {
  name                = "${var.environment}${var.location_short}acr${random_string.acr_suffix.result}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  admin_enabled       = false

  tags = var.tags
}

# Grant AKS kubelet identity pull access to ACR (AcrPull role)
# enable_aks_pull_role must be a static bool — not computed — to avoid plan-time count errors
resource "azurerm_role_assignment" "aks_acr_pull" {
  count = var.enable_aks_pull_role ? 1 : 0

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = var.aks_kubelet_identity_object_id
}
