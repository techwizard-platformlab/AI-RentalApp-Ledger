output "budget_id" {
  description = "Resource ID of the consumption budget"
  value       = azurerm_consumption_budget_resource_group.monthly.id
}

output "budget_name" {
  description = "Name of the consumption budget"
  value       = azurerm_consumption_budget_resource_group.monthly.name
}
