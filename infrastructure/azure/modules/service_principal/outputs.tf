output "client_id" { value = azuread_application.this.client_id }
output "object_id" { value = azuread_service_principal.this.object_id }
output "display_name" { value = azuread_application.this.display_name }
