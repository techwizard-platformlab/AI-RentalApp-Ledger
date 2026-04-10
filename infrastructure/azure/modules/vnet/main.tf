resource "azurerm_virtual_network" "this" {
  name                = "${var.environment}-${var.location_short}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space

  tags = var.tags
}

# Subnets are created inline (same module) to avoid the Azure API propagation
# race condition that occurs when subnets are created as separate resources
# immediately after VNet creation in a different Terraform module.
resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = "${var.environment}-${var.location_short}-${each.key}-snet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value]
}
