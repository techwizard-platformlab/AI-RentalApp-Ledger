output "vnet_id"             { value = module.vnet.id }
output "aks_name"            { value = module.aks.name }
output "acr_login_server"    { value = module.acr.login_server }
output "keyvault_uri"        { value = module.keyvault.vault_uri }
output "lb_public_ip"        { value = module.load_balancer.public_ip_address }
output "storage_account_name" { value = module.storage_account.name }
