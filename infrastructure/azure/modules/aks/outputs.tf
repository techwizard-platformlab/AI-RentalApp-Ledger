output "id" { value = azurerm_kubernetes_cluster.this.id }
output "name" { value = azurerm_kubernetes_cluster.this.name }

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive = true
}

output "kubelet_identity_object_id" {
  description = "Used to grant AcrPull on ACR"
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "principal_id" {
  description = "AKS system-assigned managed identity principal ID"
  value       = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL — used to federate K8s ServiceAccounts with Azure Managed Identities"
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}
