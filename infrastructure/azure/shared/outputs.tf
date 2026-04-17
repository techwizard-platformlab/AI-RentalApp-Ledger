output "acr_name" {
  description = "ACR short name — add as GitHub Secret ACR_NAME"
  value       = azurerm_container_registry.shared.name
}

output "acr_login_server" {
  description = "ACR login server URL — add as GitHub Secret ACR_LOGIN_SERVER"
  value       = azurerm_container_registry.shared.login_server
}
