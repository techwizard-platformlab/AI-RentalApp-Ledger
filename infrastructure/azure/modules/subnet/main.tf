resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = "${var.environment}-${var.location_short}-${each.key}-snet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = [each.value]
}
