# AKS — Standard SKU (KodeKloud requires Standard; Free SKU lacks SLA)
# Cost note: Standard_B2s is the cheapest VM that comfortably runs 4 pods.
# Single node pool in dev to minimise cost; scale out for qa/prod via variables.
resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.environment}-${var.location_short}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.environment}-${var.location_short}-aks"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Standard" # KodeKloud requirement

  # System node pool
  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.vm_size          # Standard_B2s — lowest KodeKloud-allowed AKS size
    os_disk_size_gb     = var.os_disk_size_gb  # max 128 GB, keep 30 GB for cost
    vnet_subnet_id      = var.subnet_id
    type                = "VirtualMachineScaleSets"
    auto_scaling_enabled = false # disable autoscale to avoid surprise VM costs in dev
  }

  # Managed identity (no service principal credentials to rotate)
  identity {
    type = "SystemAssigned"
  }

  # Networking — use Azure CNI for proper VNet integration
  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  # Disable expensive add-ons not needed for learning
  azure_policy_enabled             = false
  http_application_routing_enabled = false

  tags = var.tags
}
