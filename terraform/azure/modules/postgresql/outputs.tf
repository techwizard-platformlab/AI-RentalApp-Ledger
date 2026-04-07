output "server_name" {
  description = "PostgreSQL Flexible Server name"
  value       = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  description = "PostgreSQL server FQDN (use as DB_HOST)"
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "database_name" {
  description = "Application database name"
  value       = azurerm_postgresql_flexible_server_database.rental.name
}

output "admin_username" {
  description = "Administrator login username"
  value       = azurerm_postgresql_flexible_server.this.administrator_login
}
