terraform {
  backend "azurerm" {
    # Values injected at runtime via terraform init -backend-config in CI:
    # -backend-config="resource_group_name=..."
    # -backend-config="storage_account_name=..."
    # -backend-config="container_name=..."
    key      = "shared.terraform.tfstate"
    use_oidc = true
  }
}
