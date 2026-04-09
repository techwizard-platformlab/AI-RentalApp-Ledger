output "ids" {
  description = "Map of subnet name → subnet ID"
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "names" {
  description = "Map of subnet name → subnet resource name"
  value       = { for k, s in azurerm_subnet.this : k => s.name }
}
