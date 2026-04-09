# =============================================================================
# Azure environment — config driven by var.environment at runtime.
# backend.tf prefix is the only per-env hardcoded value (Terraform limitation).
# =============================================================================

locals {
  env            = var.environment
  location_short = "eus"

  env_config = {
    dev = {
      vnet_cidr    = "10.0.0.0/16"
      subnet_cidrs = { aks = "10.0.1.0/24", ingress = "10.0.2.0/24", data = "10.0.3.0/24" }
      aks_nodes    = 1
      aks_vm_size  = "Standard_D2s_v3"
      waf_mode     = "Detection"
      acr_sku      = "Basic"
    }
    qa = {
      vnet_cidr    = "10.1.0.0/16"
      subnet_cidrs = { aks = "10.1.1.0/24", ingress = "10.1.2.0/24", data = "10.1.3.0/24" }
      aks_nodes    = 1
      aks_vm_size  = "Standard_B2s"
      waf_mode     = "Prevention"
      acr_sku      = "Basic"
    }
    uat = {
      vnet_cidr    = "10.2.0.0/16"
      subnet_cidrs = { aks = "10.2.1.0/24", ingress = "10.2.2.0/24", data = "10.2.3.0/24" }
      aks_nodes    = 1
      aks_vm_size  = "Standard_B2s"
      waf_mode     = "Prevention"
      acr_sku      = "Basic"
    }
    prod = {
      vnet_cidr    = "10.3.0.0/16"
      subnet_cidrs = { aks = "10.3.1.0/24", ingress = "10.3.2.0/24", data = "10.3.3.0/24" }
      aks_nodes    = 2
      aks_vm_size  = "Standard_D2s_v3"
      waf_mode     = "Prevention"
      acr_sku      = "Standard"
    }
  }

  cfg = local.env_config[local.env]

  tags = {
    env     = local.env
    project = "rentalAppLedger"
    owner   = "ramprasath"
  }
}

# ── Networking ────────────────────────────────────────────────────────────────
module "vnet" {
  source              = "../../modules/vnet"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  address_space       = [local.cfg.vnet_cidr]
  tags                = local.tags
}

module "subnet" {
  source              = "../../modules/subnet"
  environment         = local.env
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  vnet_name           = module.vnet.name
  subnets             = local.cfg.subnet_cidrs
}

module "security_group" {
  source              = "../../modules/security_group"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  subnet_ids          = module.subnet.ids
  tags                = local.tags
}

# ── Compute ───────────────────────────────────────────────────────────────────
# AKS — system node pool + dedicated appnode pool for application workloads.
# Destroy AKS when not in use to save ~$0.19/hr. ACR and SQL persist.
module "aks" {
  source              = "../../modules/aks"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  kubernetes_version  = null
  node_count          = local.cfg.aks_nodes
  vm_size             = local.cfg.aks_vm_size
  os_disk_size_gb     = 30
  subnet_id           = module.subnet.ids["aks"]
  tags                = local.tags
}

# ACR — persists between deploys (daily billing, no hourly cost when AKS is down)
module "acr" {
  source              = "../../modules/acr"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  sku                 = local.cfg.acr_sku
  tags                = local.tags
}

module "load_balancer" {
  source              = "../../modules/load_balancer"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

# ── Security / Storage ────────────────────────────────────────────────────────
module "keyvault" {
  source              = "../../modules/keyvault"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  sku                 = "standard"
  soft_delete_days    = 7
  cicd_sp_object_id   = var.cicd_sp_object_id
  tags                = local.tags
}

# Azure SQL Database — persists between deploys (data retained across sessions)
# Basic tier: 5 DTUs, 2 GB — sufficient for dev/learning workloads
module "sql_database" {
  source              = "../../modules/sql_database"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  db_sku              = "Basic"
  max_size_gb         = 2
  aks_subnet_cidr     = local.cfg.subnet_cidrs["aks"]
  key_vault_name      = module.keyvault.name
  tags                = local.tags

  depends_on = [module.keyvault]
}

module "storage_account" {
  source              = "../../modules/storage_account"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  suffix              = "app"
  containers          = ["uploads", "backups"]
  tags                = local.tags
}

# ── Cost Management ───────────────────────────────────────────────────────────
# Weekly budget alert — notifies when spend approaches 400 INR (~$5/week).
# All resources share one resource group, making deletion simple:
#   az group delete --name <rg> --yes
module "budget" {
  source              = "../../modules/budget"
  environment         = local.env
  resource_group_name = var.resource_group_name
  weekly_budget_usd   = 5
  budget_start_date   = "2026-04-01T00:00:00Z"
  alert_emails        = var.alert_emails
}
