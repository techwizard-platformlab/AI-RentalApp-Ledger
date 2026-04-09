# Public IP for Load Balancer — Standard SKU required with AKS Standard
# Cost note: Standard public IP ~$0.005/hr when associated; ~$0.004/hr idle.
resource "azurerm_public_ip" "this" {
  name                = "${var.environment}-${var.location_short}-lb-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard" # must match LB SKU
  tags                = var.tags
}

# Standard Load Balancer — required for AKS Standard SKU
resource "azurerm_lb" "this" {
  name                = "${var.environment}-${var.location_short}-lb"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard" # Standard SKU required for AKS
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.this.id
  }
}

resource "azurerm_lb_backend_address_pool" "this" {
  name            = "${var.environment}-${var.location_short}-lb-bap"
  loadbalancer_id = azurerm_lb.this.id
}
