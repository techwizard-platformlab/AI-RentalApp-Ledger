# =============================================================================
# Azure dev environment — fully self-contained in my-Rental-App-Dev
# Manages: ACR, AKS, VNet, NSG, Load Balancer, Database, Storage, Key Vault
#
# All resources live in my-Rental-App-Dev.
# compute-only destroy: AKS, LB, NSG, subnet, VNet (ACR, DB, KV, Storage kept)
# full destroy:         entire resource group
#
# Database engine — controlled by var.db_engine in terraform.tfvars:
#   postgresql (default) → PostgreSQL Flexible Server
#   mssql                → Azure SQL Database
# =============================================================================

# ── Env resource group ────────────────────────────────────────────────────────
resource "azurerm_resource_group" "env" {
  name     = var.env_resource_group_name
  location = var.location
  tags     = local.tags
}

# ── Container Registry — env-specific, persists across compute destroy ────────
resource "random_string" "acr_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_container_registry" "env" {
  name                = "${var.environment}${var.location_short}acr${random_string.acr_suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.env.name
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = local.tags
}

# AcrPush — GitHub Actions CI/CD can push images to this registry
resource "azurerm_role_assignment" "github_acr_push" {
  scope                = azurerm_container_registry.env.id
  role_definition_name = "AcrPush"
  principal_id         = var.github_actions_principal_id
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

# Store ACR login server in Key Vault for app consumption
resource "azurerm_key_vault_secret" "acr_login_server" {
  name         = "acr-login-server"
  value        = azurerm_container_registry.env.login_server
  key_vault_id = module.keyvault.id
  depends_on   = [azurerm_role_assignment.github_kv_secrets_officer]
}

# Push ACR secrets to GitHub
resource "github_actions_secret" "acr_login_server" {
  repository      = var.app_github_repo
  secret_name     = "ACR_LOGIN_SERVER"
  plaintext_value = azurerm_container_registry.env.login_server
}

resource "github_actions_secret" "acr_name" {
  repository      = var.app_github_repo
  secret_name     = "ACR_NAME"
  plaintext_value = azurerm_container_registry.env.name
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
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
  tags                = local.tags
}

# AcrPull — AKS pods can pull images from the env registry
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.env.id
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
  depends_on          = [azurerm_role_assignment.github_kv_secrets_officer]
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
  depends_on          = [azurerm_role_assignment.github_kv_secrets_officer]
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

# ── External Secrets Operator identity ───────────────────────────────────────
# Allows the ESO pod (running in AKS) to read secrets from Key Vault
# without any static credentials — uses federated workload identity.
resource "azurerm_user_assigned_identity" "eso" {
  name                = "${var.environment}-${var.location_short}-eso-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.env.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "eso_kv_secrets_user" {
  scope                = module.keyvault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.eso.principal_id
  depends_on           = [module.keyvault]
}

# Links the K8s ServiceAccount "external-secrets" (in ns "external-secrets")
# to the managed identity above — no client secret required.
resource "azurerm_federated_identity_credential" "eso" {
  name                      = "eso-federated"
  user_assigned_identity_id = azurerm_user_assigned_identity.eso.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = module.aks.oidc_issuer_url
  subject                   = "system:serviceaccount:external-secrets:external-secrets"
  depends_on                = [module.aks]
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
