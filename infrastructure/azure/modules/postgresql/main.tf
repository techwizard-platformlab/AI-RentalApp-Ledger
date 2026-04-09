# =============================================================================
# Azure Database for PostgreSQL Flexible Server
# SKU: Burstable B1ms — cheapest tier, suitable for dev environments.
# Public access with IP firewall rules (no VNet integration to keep it simple).
# =============================================================================

# Random password for DB admin (generated once, stored in Key Vault)
resource "random_password" "db_admin" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# Random Django SECRET_KEY
resource "random_password" "django_secret_key" {
  length  = 64
  special = true
}

# ── PostgreSQL Flexible Server ─────────────────────────────────────────────────
resource "azurerm_postgresql_flexible_server" "this" {
  name                   = "${var.environment}-${var.location_short}-psql"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = "16"
  administrator_login    = var.db_admin_username
  administrator_password = random_password.db_admin.result

  storage_mb   = 32768   # 32 GiB minimum
  storage_tier = "P4"

  sku_name = "B_Standard_B1ms"   # Burstable 1 vCore — lowest cost tier

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  # Public access — firewall rules control which IPs can connect
  public_network_access_enabled = true

  tags = var.tags

  lifecycle {
    ignore_changes = [
      # Password managed by random_password, not drift-detected
      administrator_password,
      # Zone is assigned by Azure automatically
      zone,
    ]
  }
}

# ── Application database ───────────────────────────────────────────────────────
resource "azurerm_postgresql_flexible_server_database" "rental" {
  name      = "rental_db"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ── Firewall: allow Azure services (AKS pods use Azure IPs) ───────────────────
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ── Firewall: allow AKS subnet CIDR (for direct pod → DB connections) ─────────
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_aks" {
  name             = "allow-aks-subnet"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = cidrhost(var.aks_subnet_cidr, 0)
  end_ip_address   = cidrhost(var.aks_subnet_cidr, -1)
}

# ── Key Vault secrets ──────────────────────────────────────────────────────────
resource "azurerm_key_vault_secret" "db_host" {
  name         = "db-host"
  value        = azurerm_postgresql_flexible_server.this.fqdn
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "db_name" {
  name         = "db-name"
  value        = azurerm_postgresql_flexible_server_database.rental.name
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "db_user" {
  name         = "db-user"
  value        = var.db_admin_username
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = random_password.db_admin.result
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "db_port" {
  name         = "db-port"
  value        = "5432"
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "django_secret_key" {
  name         = "django-secret-key"
  value        = random_password.django_secret_key.result
  key_vault_id = var.key_vault_id
}
