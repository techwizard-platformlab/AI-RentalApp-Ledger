output "id" { value = azurerm_virtual_network.this.id }
output "name" { value = azurerm_virtual_network.this.name }

output "subnet_ids" {
  description = "Map of subnet key → subnet ID"
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "subnet_names" {
  description = "Map of subnet key → subnet resource name"
  value       = { for k, s in azurerm_subnet.this : k => s.name }
}
