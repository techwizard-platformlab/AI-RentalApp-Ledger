output "server_name" {
  description = "SQL Server logical server name"
  value       = azurerm_mssql_server.this.name
}

output "fqdn" {
  description = "SQL Server FQDN (use as DB_HOST)"
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "database_name" {
  description = "SQL Database name"
  value       = azurerm_mssql_database.rental.name
}

output "admin_username" {
  description = "SQL Server administrator login"
  value       = azurerm_mssql_server.this.administrator_login
}

output "port" {
  description = "SQL Server port"
  value       = 1433
}
