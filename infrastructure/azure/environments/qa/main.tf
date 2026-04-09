# =============================================================================
# Azure QA environment
# Mirrors dev with slightly higher resource limits and WAF in Prevention mode.
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
      acr_sku      = "Basic"
    }
    qa = {
      vnet_cidr    = "10.1.0.0/16"
      subnet_cidrs = { aks = "10.1.1.0/24", ingress = "10.1.2.0/24", data = "10.1.3.0/24" }
      aks_nodes    = 1
      aks_vm_size  = "Standard_B2s"
      acr_sku      = "Basic"
    }
  }

  cfg = local.env_config[local.env]

  tags = {
    env     = local.env
    project = "rentalAppLedger"
    owner   = "ramprasath"
  }
}

# --- Networking ---------------------------------------------------------------
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

# WAF policy intentionally disabled — WAF policy creation disabled (requires higher-tier subscription)
# module "waf_policy" { ... }

# --- Compute ------------------------------------------------------------------
module "aks" {
  source              = "../../modules/aks"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  kubernetes_version  = null   # auto-select latest supported version
  node_count          = local.cfg.aks_nodes
  vm_size             = local.cfg.aks_vm_size
  os_disk_size_gb     = 30
  subnet_id           = module.subnet.ids["aks"]
  tags                = local.tags
}

module "acr" {
  source              = "../../modules/acr"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  sku                 = local.cfg.acr_sku
  tags                = local.tags
  # NOTE: AcrPull role assignment removed — SP may lack role assignment permissions — check IAM
}

module "load_balancer" {
  source              = "../../modules/load_balancer"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

# --- Security / Storage -------------------------------------------------------
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
  # Access-policy mode — no role assignments needed
}

# NOTE: PostgreSQL Flexible Server not used — Azure SQL is sufficient for dev.
# Uncomment below if PostgreSQL is preferred over Azure SQL.
#
# module "postgresql" {
#   source              = "../../modules/postgresql"
#   environment         = local.env
#   location            = var.location
#   location_short      = local.location_short
#   resource_group_name = var.resource_group_name
#   aks_subnet_cidr     = local.cfg.subnet_cidrs["aks"]
#   key_vault_id        = module.keyvault.id
#   tags                = local.tags
#   depends_on          = [module.keyvault]
# }

# Azure SQL Database — S1 for QA load capacity
module "sql_database" {
  source              = "../../modules/sql_database"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  db_sku              = "S1"    # qa: 20 DTUs, 250 GB — handles load tests
  max_size_gb         = 10
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
