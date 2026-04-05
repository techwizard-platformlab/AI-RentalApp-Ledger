resource "azurerm_virtual_network" "this" {
  name                = "${var.environment}-${var.location_short}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space

  tags = var.tags
}
