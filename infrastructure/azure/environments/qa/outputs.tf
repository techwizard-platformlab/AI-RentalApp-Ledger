output "vnet_id"              { value = module.vnet.id }
output "aks_name"             { value = module.aks.name }
output "acr_name"             { value = data.azurerm_container_registry.shared.name }
output "acr_login_server"     { value = data.azurerm_container_registry.shared.login_server }
output "key_vault_name"       { value = data.azurerm_key_vault.shared.name }
output "key_vault_uri"        { value = data.azurerm_key_vault.shared.vault_uri }
output "lb_public_ip"         { value = module.load_balancer.public_ip_address }
output "storage_account_name" { value = module.storage_account.name }

output "db_engine" {
  description = "Database engine deployed (postgresql or mssql)"
  value       = var.db_engine
}

output "db_server_fqdn" {
  description = "Database server FQDN (host for Django DB_HOST)"
  value = var.db_engine == "postgresql" ? (
    length(module.postgresql) > 0 ? module.postgresql[0].fqdn : null
  ) : (
    length(module.sql_database) > 0 ? module.sql_database[0].fqdn : null
  )
}

output "db_name" {
  description = "Application database name"
  value = var.db_engine == "postgresql" ? (
    length(module.postgresql) > 0 ? module.postgresql[0].database_name : null
  ) : (
    length(module.sql_database) > 0 ? module.sql_database[0].database_name : null
  )
}

output "db_admin_username" {
  description = "Database administrator username"
  value = var.db_engine == "postgresql" ? (
    length(module.postgresql) > 0 ? module.postgresql[0].admin_username : null
  ) : (
    length(module.sql_database) > 0 ? module.sql_database[0].admin_username : null
  )
}
