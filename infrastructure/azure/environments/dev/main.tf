# =============================================================================
# Azure dev environment
# Manages: AKS, VNet, Subnets, NSG, Load Balancer, Database, Storage, Key Vault
#
# Database engine — controlled by var.db_engine in terraform.tfvars:
#   postgresql (default) → PostgreSQL Flexible Server (B_Standard_B1ms, ~$12/month)
#   mssql                → Azure SQL Database (Basic, ~$5/month)
# Only one module is deployed; the other has count = 0.
#
# Key Vault is env-specific — manages dev secrets only.
# ACR is shared — referenced via data source; AcrPull granted to AKS here.
#
# Resource group: my-Rental-App-Dev (destroy-safe — shared RG untouched)
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
    uat = {
      vnet_cidr    = "10.2.0.0/16"
      subnet_cidrs = { aks = "10.2.1.0/24", ingress = "10.2.2.0/24", data = "10.2.3.0/24" }
      aks_nodes    = 1
      aks_vm_size  = "Standard_B2s"
    }
    prod = {
      vnet_cidr    = "10.3.0.0/16"
      subnet_cidrs = { aks = "10.3.1.0/24", ingress = "10.3.2.0/24", data = "10.3.3.0/24" }
      aks_nodes    = 2
      aks_vm_size  = "Standard_D2s_v3"
    }
  }

  cfg = local.env_config[local.env]

  tags = {
    env     = local.env
    project = "rentalAppLedger"
    owner   = "techwizard-platformlab"
  }
}

# ── Env resource group ────────────────────────────────────────────────────────
resource "azurerm_resource_group" "env" {
  name     = var.env_resource_group_name
  location = var.location
  tags     = local.tags
}

# ── Shared ACR reference ──────────────────────────────────────────────────────
data "azurerm_container_registry" "shared" {
  name                = var.acr_name
  resource_group_name = var.shared_resource_group_name
}

# ── Key Vault — env-specific secrets ─────────────────────────────────────────
module "keyvault" {
  source              = "../../modules/keyvault"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  tags                = local.tags
}

# Key Vault Secrets Officer — GitHub Actions CI/CD can read and write secrets
resource "azurerm_role_assignment" "github_kv_secrets_officer" {
  scope                = module.keyvault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.github_actions_principal_id
  depends_on           = [module.keyvault]
}

# Store shared ACR login server URL in env Key Vault for app consumption
resource "azurerm_key_vault_secret" "acr_login_server" {
  name         = "acr-login-server"
  value        = data.azurerm_container_registry.shared.login_server
  key_vault_id = module.keyvault.id
  depends_on   = [azurerm_role_assignment.github_kv_secrets_officer]
}

# ── Networking ────────────────────────────────────────────────────────────────
module "vnet" {
  source              = "../../modules/vnet"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  address_space       = [local.cfg.vnet_cidr]
  subnets             = local.cfg.subnet_cidrs
  tags                = local.tags
}

module "security_group" {
  source              = "../../modules/security_group"
  environment         = local.env
  location            = var.location
  location_short      = local.location_short
  resource_group_name = azurerm_resource_group.env.name
  subnet_ids          = module.vnet.subnet_ids
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
  subnet_id           = module.vnet.subnet_ids["aks"]
  tags                = local.tags
}

# AcrPull — AKS pods can pull images from the shared registry
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
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
  key_vault_id        = module.keyvault.id
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
  key_vault_name      = module.keyvault.name
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
