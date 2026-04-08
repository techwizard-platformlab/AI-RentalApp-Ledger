# =============================================================================
# Azure SQL Database (SQL Server + Database)
# KodeKloud allowed tiers: Basic, S0–S4 | Max size: 50 GB | Max 2 instances
# Backup redundancy: Local only
#
# dev  → Basic  (5 DTUs,  2 GB,  ~$5/month)
# qa   → S1     (20 DTUs, 250 GB, ~$30/month)
# =============================================================================

# Random password for SQL admin
resource "random_password" "sql_admin" {
  length           = 32
  special          = true
  override_special = "!#$%-_=+?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# Random Django SECRET_KEY
resource "random_password" "django_secret_key" {
  length  = 64
  special = false   # avoid shell quoting issues in K8s secrets
}

# ── SQL Logical Server ─────────────────────────────────────────────────────────
resource "azurerm_mssql_server" "this" {
  name                         = "${var.environment}-${var.location_short}-sqlsrv"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = random_password.sql_admin.result

  # Disable public network access — use firewall rules instead
  public_network_access_enabled = true   # required for AKS egress without private endpoint

  tags = var.tags

  lifecycle {
    ignore_changes  = [administrator_login_password]
    prevent_destroy = true   # data loss protection — use 'terraform state rm' to override
  }
}

# ── SQL Database ───────────────────────────────────────────────────────────────
resource "azurerm_mssql_database" "rental" {
  name      = "rental-db"
  server_id = azurerm_mssql_server.this.id

  # KodeKloud allowed SKUs — Basic for dev, S0/S1 for qa
  sku_name   = var.db_sku
  max_size_gb = var.max_size_gb

  # KodeKloud only allows Local backup redundancy
  storage_account_type = "Local"

  tags = var.tags

  lifecycle {
    # storage_account_type and max_size_gb drift between Azure API response ("LocallyRedundant")
    # and provider value ("Local"), causing a ForceNew replace on every apply.
    ignore_changes  = [storage_account_type, max_size_gb]
    prevent_destroy = true   # data loss protection — use 'terraform state rm' to override
  }
}

# ── Firewall: allow Azure services (AKS egress IPs are Azure IPs) ─────────────
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ── Firewall: allow AKS subnet ─────────────────────────────────────────────────
resource "azurerm_mssql_firewall_rule" "allow_aks" {
  name             = "allow-aks-subnet"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = cidrhost(var.aks_subnet_cidr, 0)
  end_ip_address   = cidrhost(var.aks_subnet_cidr, -1)
}

# ── Key Vault secrets via az CLI (local-exec) ──────────────────────────────────
# azurerm_key_vault_secret requires Key Vault Secrets Officer via RBAC role assignment.
# KodeKloud blocks role assignments (403). However, the KodeKloud lab SP is pre-assigned
# Key Vault Secrets Officer at the subscription level, so az keyvault secret set works.
# Using local-exec with az CLI avoids the Terraform provider RBAC check entirely.
resource "null_resource" "kv_secrets" {
  triggers = {
    server_fqdn  = azurerm_mssql_server.this.fully_qualified_domain_name
    db_name      = azurerm_mssql_database.rental.name
    kv_name      = var.key_vault_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      az keyvault secret set --vault-name "${var.key_vault_name}" --name "db-host"          --value "${azurerm_mssql_server.this.fully_qualified_domain_name}" --output none
      az keyvault secret set --vault-name "${var.key_vault_name}" --name "db-name"          --value "${azurerm_mssql_database.rental.name}"                   --output none
      az keyvault secret set --vault-name "${var.key_vault_name}" --name "db-user"          --value "${var.sql_admin_username}"                               --output none
      az keyvault secret set --vault-name "${var.key_vault_name}" --name "db-password"      --value "${random_password.sql_admin.result}"                     --output none
      az keyvault secret set --vault-name "${var.key_vault_name}" --name "db-port"          --value "1433"                                                    --output none
      az keyvault secret set --vault-name "${var.key_vault_name}" --name "db-engine"        --value "mssql"                                                   --output none
      az keyvault secret set --vault-name "${var.key_vault_name}" --name "django-secret-key" --value "${random_password.django_secret_key.result}"            --output none
    EOT
  }

  depends_on = [
    azurerm_mssql_server.this,
    azurerm_mssql_database.rental,
  ]
}
