# AKS — KodeKloud allowed VM sizes: Standard_D2s_v3, Standard_K8S2_v1, Standard_K8S_v1
# Max agent pool: 2. Max node pool: 1. Container insights must be disabled.
resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.environment}-${var.location_short}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.environment}-${var.location_short}-aks"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"   # Standard costs $0.10/hr and triggers agentPools/write on update; Free avoids both

  default_node_pool {
    name                 = "system"
    node_count           = var.node_count
    vm_size              = var.vm_size
    os_disk_size_gb      = var.os_disk_size_gb
    vnet_subnet_id       = var.subnet_id
    type                 = "VirtualMachineScaleSets"
    auto_scaling_enabled = false
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    load_balancer_sku  = "standard"
    outbound_type      = "loadBalancer"
    # Must not overlap with VNet (10.0.0.0/16) or subnets (10.0.1-3.0/24)
    service_cidr       = "10.1.0.0/16"
    dns_service_ip     = "10.1.0.10"
  }

  # KodeKloud policy: disable all add-ons including container insights
  azure_policy_enabled             = false
  http_application_routing_enabled = false
  # oms_agent block intentionally omitted — disables container insights per KodeKloud policy

  # OIDC issuer — once enabled it cannot be disabled (Azure platform restriction).
  # Keep true to match existing cluster state and avoid 400 OIDCIssuerFeatureCannotBeDisabled.
  oidc_issuer_enabled      = true
  workload_identity_enabled = false   # not needed; keep OIDC issuer only

  tags = var.tags

  lifecycle {
    ignore_changes = [
      # kubernetes_version is managed by AKS auto-upgrade — let Azure control it
      kubernetes_version,
      # KodeKloud SP lacks Microsoft.ContainerService/managedClusters/agentPools/write.
      # Any cluster PUT request includes the node pool in the body → 403.
      # Ignoring default_node_pool prevents Terraform from ever sending node pool diffs.
      # To change node pool settings, use the Azure Portal.
      default_node_pool,
      # sku_tier drift also triggers a node pool update — ignore it
      sku_tier,
      # NOTE: oidc_issuer_enabled is intentionally NOT here.
      # Code has true → Terraform always sends true → no 400 OIDCIssuerFeatureCannotBeDisabled.
      # Having it in ignore_changes caused Terraform to send the old state value (false) → error.
    ]
  }
}
