# =============================================================================
# Azure QA environment
# Mirrors dev with higher resource limits for load testing.
#
# Database engine — controlled by var.db_engine in terraform.tfvars:
#   postgresql (default) → PostgreSQL Flexible Server (B_Standard_B1ms, ~$12/month)
#   mssql                → Azure SQL Database (S1, ~$15/month)
# Only one module is deployed; the other has count = 0.
#
# Key Vault is env-specific — manages qa secrets only.
# ACR is shared — referenced via data source; AcrPull granted to AKS here.
#
# Resource group: my-Rental-App-QA (destroy-safe)
# =============================================================================

# ── Env resource group ────────────────────────────────────────────────────────
resource "azurerm_resource_group" "env" {
  name     = var.env_resource_group_name
  location = var.location
  tags     = local.tags
}

# ── Shared ACR reference ──────────────────────────────────────────────────────
# Skipped when acr_name is empty (shared layer not yet applied).
data "azurerm_container_registry" "shared" {
  count               = local.acr_ready ? 1 : 0
  name                = var.acr_name
  resource_group_name = var.shared_resource_group_name
}

# ── Key Vault — env-specific secrets ─────────────────────────────────────────
module "keyvault" {
  source              = "../../modules/keyvault"
  environment         = var.environment
  location            = var.location
  location_short      = var.location_short
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
  count        = local.acr_ready ? 1 : 0
  name         = "acr-login-server"
  value        = data.azurerm_container_registry.shared[0].login_server
  key_vault_id = module.keyvault.id
  depends_on   = [azurerm_role_assignment.github_kv_secrets_officer]
}

# ── Networking ────────────────────────────────────────────────────────────────
module "vnet" {
  source              = "../../modules/vnet"
  environment         = var.environment
  location            = var.location
  location_short      = var.location_short
  resource_group_name = azurerm_resource_group.env.name
  address_space       = [var.vnet_cidr]
  subnets             = var.subnet_cidrs
  tags                = local.tags
}

module "security_group" {
  source              = "../../modules/security_group"
  environment         = var.environment
  location            = var.location
  location_short      = var.location_short
  resource_group_name = azurerm_resource_group.env.name
  subnet_ids          = module.vnet.subnet_ids
  tags                = local.tags
}

# ── Compute ───────────────────────────────────────────────────────────────────
module "aks" {
  source              = "../../modules/aks"
  environment         = var.environment
  location            = var.location
  location_short      = var.location_short
  resource_group_name = azurerm_resource_group.env.name
  kubernetes_version  = var.kubernetes_version
  node_count          = var.aks_node_count
  vm_size             = var.aks_vm_size
  os_disk_size_gb     = var.aks_os_disk_gb
  subnet_id           = module.vnet.subnet_ids["aks"]
  tags                = local.tags
}

# AcrPull — AKS pods can pull images from the shared registry
resource "azurerm_role_assignment" "aks_acr_pull" {
  count                = local.acr_ready ? 1 : 0
  scope                = data.azurerm_container_registry.shared[0].id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}

module "load_balancer" {
  source              = "../../modules/load_balancer"
  environment         = var.environment
  location            = var.location
  location_short      = var.location_short
  resource_group_name = azurerm_resource_group.env.name
  tags                = local.tags
}

# ── Data storage ──────────────────────────────────────────────────────────────
# Exactly one database module is deployed, chosen by var.db_engine (terraform.tfvars).

module "postgresql" {
  count  = var.db_engine == "postgresql" ? 1 : 0
  source = "../../modules/postgresql"

  environment         = var.environment
  location            = var.location
  location_short      = var.location_short
  resource_group_name = azurerm_resource_group.env.name
  sku_name            = var.postgresql_sku
  storage_mb          = var.postgresql_storage_mb
  storage_tier        = var.postgresql_storage_tier
  aks_subnet_cidr     = var.subnet_cidrs["aks"]
  key_vault_id        = module.keyvault.id
  tags                = local.tags
}

module "sql_database" {
  count  = var.db_engine == "mssql" ? 1 : 0
  source = "../../modules/sql_database"

  environment         = var.environment
  location            = var.location
  location_short      = var.location_short
  resource_group_name = azurerm_resource_group.env.name
  db_sku              = var.mssql_sku
  max_size_gb         = var.mssql_max_size_gb
  aks_subnet_cidr     = var.subnet_cidrs["aks"]
  key_vault_name      = module.keyvault.name
  tags                = local.tags
}

module "storage_account" {
  source              = "../../modules/storage_account"
  environment         = var.environment
  location            = var.location
  location_short      = var.location_short
  resource_group_name = azurerm_resource_group.env.name
  suffix              = "app"
  containers          = var.app_storage_containers
  tags                = local.tags
}

# ── Cost management ───────────────────────────────────────────────────────────
module "budget" {
  source             = "../../modules/budget"
  environment        = var.environment
  resource_group_id  = azurerm_resource_group.env.id
  monthly_budget_usd = var.monthly_budget_usd
  budget_start_date  = var.budget_start_date
  alert_emails       = var.alert_emails
}
