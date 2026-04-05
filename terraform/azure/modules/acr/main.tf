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

# NOTE: AcrPull role assignment intentionally removed — KodeKloud blocks
# Microsoft.Authorization/roleAssignments (403). Assign manually via Azure Portal if needed.
