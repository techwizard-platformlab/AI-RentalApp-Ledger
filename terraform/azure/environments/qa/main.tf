# =============================================================================
# Azure environment — all config is driven by var.environment at runtime.
# The directory (dev/) exists only to hold the env-specific backend.tf.
# CI passes: -var="environment=dev"  (or qa / uat / prod)
#
# NOTE: backend.tf prefix is intentionally hardcoded — Terraform does not
# support variables in backend configuration. That is the only per-env
# hardcoded value in this file.
# =============================================================================

# ── Per-environment config lookup ─────────────────────────────────────────────
# Add a new row here when onboarding a new environment.
# All other resource definitions below are environment-agnostic.
locals {
  env            = var.environment
  location_short = "eus"

  env_config = {
    dev = {
      vnet_cidr     = "10.0.0.0/16"
      subnet_cidrs  = { aks = "10.0.1.0/24", ingress = "10.0.2.0/24", data = "10.0.3.0/24" }
      aks_nodes     = 1
      aks_vm_size   = "Standard_B2s"
      waf_mode      = "Detection"   # no traffic blocked in dev
      acr_sku       = "Basic"
    }
    qa = {
      vnet_cidr     = "10.1.0.0/16"
      subnet_cidrs  = { aks = "10.1.1.0/24", ingress = "10.1.2.0/24", data = "10.1.3.0/24" }
      aks_nodes     = 1
      aks_vm_size   = "Standard_B2s"
      waf_mode      = "Prevention"  # enforce in qa+
      acr_sku       = "Basic"
    }
    uat = {
      vnet_cidr     = "10.2.0.0/16"
      subnet_cidrs  = { aks = "10.2.1.0/24", ingress = "10.2.2.0/24", data = "10.2.3.0/24" }
      aks_nodes     = 1
      aks_vm_size   = "Standard_B2s"
      waf_mode      = "Prevention"
      acr_sku       = "Basic"
    }
    prod = {
      vnet_cidr     = "10.3.0.0/16"
      subnet_cidrs  = { aks = "10.3.1.0/24", ingress = "10.3.2.0/24", data = "10.3.3.0/24" }
      aks_nodes     = 2
      aks_vm_size   = "Standard_D2s_v3"
      waf_mode      = "Prevention"
      acr_sku       = "Standard"
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

module "waf_policy" {
  source              = "../../modules/waf_policy"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  waf_mode            = local.cfg.waf_mode
  tags                = local.tags
}

# --- Compute ------------------------------------------------------------------
module "aks" {
  source              = "../../modules/aks"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  kubernetes_version  = "1.29"
  node_count          = local.cfg.aks_nodes
  vm_size             = local.cfg.aks_vm_size
  os_disk_size_gb     = 30
  subnet_id           = module.subnet.ids["aks"]
  tags                = local.tags
}

module "acr" {
  source                         = "../../modules/acr"
  environment                    = local.env
  location                       = var.location
  location_short                 = local.location_short
  resource_group_name            = var.resource_group_name
  sku                            = local.cfg.acr_sku
  aks_kubelet_identity_object_id = module.aks.kubelet_identity_object_id
  tags                           = local.tags
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
  # Access-policy mode — no role assignments needed (KodeKloud compatible)
}

# NOTE: PostgreSQL Flexible Server is blocked on KodeKloud.
# Uncomment below when running on a full Azure subscription.
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

# Azure SQL Database — KodeKloud allowed (S1 for QA load capacity)
module "sql_database" {
  source              = "../../modules/sql_database"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = var.resource_group_name
  db_sku              = "S1"    # qa: 20 DTUs, 250 GB — handles load tests
  max_size_gb         = 10
  aks_subnet_cidr     = local.cfg.subnet_cidrs["aks"]
  key_vault_id        = module.keyvault.id
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
