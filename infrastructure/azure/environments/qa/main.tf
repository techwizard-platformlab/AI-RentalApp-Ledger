# =============================================================================
# Azure QA environment
# Mirrors dev with higher resource limits for load testing.
#
# Database engine — controlled by var.db_engine in terraform.tfvars:
#   postgresql (default) → PostgreSQL Flexible Server (B_Standard_B1ms, ~$12/month)
#   mssql                → Azure SQL Database (S1, ~$15/month)
# Only one module is deployed; the other has count = 0.
#
# Does NOT manage: ACR, Key Vault (shared — see infrastructure/azure/shared/)
# Resource group: my-Rental-App-QA (destroy-safe)
# =============================================================================

locals {
  env            = var.environment
  location_short = "eus2"

  env_config = {
    dev = {
      vnet_cidr    = "10.0.0.0/16"
      subnet_cidrs = { aks = "10.0.1.0/24", ingress = "10.0.2.0/24", data = "10.0.3.0/24" }
      aks_nodes    = 1
      aks_vm_size  = "Standard_D2s_v3"
    }
    qa = {
      vnet_cidr    = "10.1.0.0/16"
      subnet_cidrs = { aks = "10.1.1.0/24", ingress = "10.1.2.0/24", data = "10.1.3.0/24" }
      aks_nodes    = 1
      aks_vm_size  = "Standard_B2s"
    }
  }

  cfg = local.env_config[local.env]

  tags = {
    env     = local.env
    project = "rentalAppLedger"
    owner   = "techwizard-platformlab"
  }
}

# ── Env resource group (Terraform-owned — destroyed with the environment) ─────
resource "azurerm_resource_group" "env" {
  name     = var.env_resource_group_name
  location = var.location
  tags     = local.tags
}

# ── Shared resource references (data sources — not managed here) ──────────────
# Conditional: skipped if shared layer has not yet run (acr_name / key_vault_name empty).
locals {
  shared_ready = var.acr_name != "" && var.key_vault_name != ""
}

data "azurerm_container_registry" "shared" {
  count               = local.shared_ready ? 1 : 0
  name                = var.acr_name
  resource_group_name = var.shared_resource_group_name
}

data "azurerm_key_vault" "shared" {
  count               = local.shared_ready ? 1 : 0
  name                = var.key_vault_name
  resource_group_name = var.shared_resource_group_name
}

# ── Networking ────────────────────────────────────────────────────────────────
module "vnet" {
  source              = "../../modules/vnet"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  address_space       = [local.cfg.vnet_cidr]
  tags                = local.tags
}

module "subnet" {
  source              = "../../modules/subnet"
  environment         = local.env
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  vnet_name           = module.vnet.name
  subnets             = local.cfg.subnet_cidrs
}

module "security_group" {
  source              = "../../modules/security_group"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  subnet_ids          = module.subnet.ids
  tags                = local.tags
}

# ── Compute ───────────────────────────────────────────────────────────────────
module "aks" {
  source              = "../../modules/aks"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  kubernetes_version  = null
  node_count          = local.cfg.aks_nodes
  vm_size             = local.cfg.aks_vm_size
  os_disk_size_gb     = 30
  subnet_id           = module.subnet.ids["aks"]
  tags                = local.tags
}

module "load_balancer" {
  source              = "../../modules/load_balancer"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  tags                = local.tags
}

# ── Data storage ──────────────────────────────────────────────────────────────
# Exactly one database module is deployed, chosen by var.db_engine (terraform.tfvars).
# Default: postgresql. To switch to Azure SQL set db_engine = "mssql" in tfvars.
# Secrets are written to the shared Key Vault by each module.

module "postgresql" {
  count  = var.db_engine == "postgresql" ? 1 : 0
  source = "../../modules/postgresql"

  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  sku_name            = var.postgresql_sku
  storage_mb          = var.postgresql_storage_mb
  storage_tier        = var.postgresql_storage_tier
  aks_subnet_cidr     = local.cfg.subnet_cidrs["aks"]
  key_vault_id        = local.shared_ready ? data.azurerm_key_vault.shared[0].id : null
  tags                = local.tags
}

module "sql_database" {
  count  = var.db_engine == "mssql" ? 1 : 0
  source = "../../modules/sql_database"

  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  db_sku              = var.mssql_sku
  max_size_gb         = var.mssql_max_size_gb
  aks_subnet_cidr     = local.cfg.subnet_cidrs["aks"]
  key_vault_name      = local.shared_ready ? data.azurerm_key_vault.shared[0].name : null
  tags                = local.tags
}

module "storage_account" {
  source              = "../../modules/storage_account"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  suffix              = "app"
  containers          = ["uploads", "backups"]
  tags                = local.tags
}

# ── Cost management ───────────────────────────────────────────────────────────
module "budget" {
  source             = "../../modules/budget"
  environment        = local.env
  resource_group_id  = azurerm_resource_group.env.id
  monthly_budget_usd = 22
  budget_start_date  = "2026-04-01T00:00:00Z"
  alert_emails       = var.alert_emails
}
