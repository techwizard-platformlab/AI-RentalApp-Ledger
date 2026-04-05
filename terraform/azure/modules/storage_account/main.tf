# Storage Account — Standard_LRS is cheapest (no redundancy needed for app data in dev)
# Cost note: Standard_LRS ~$0.018/GB/month. ZRS/GRS are more expensive — skip for learning.
resource "azurerm_storage_account" "this" {
  name                     = "${var.environment}${var.location_short}sa${var.suffix}" # globally unique
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"       # LRS = cheapest; no geo-redundancy for dev
  account_kind             = "StorageV2"

  https_traffic_only_enabled       = true  # enforce HTTPS
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false # block anonymous blob access

  tags = var.tags
}

resource "azurerm_storage_container" "this" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
