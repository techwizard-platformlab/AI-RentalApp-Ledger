terraform {
  backend "azurerm" {
    # Values injected at runtime via terraform init -backend-config in CI
    key      = "qa.terraform.tfstate"
    use_oidc = false
  }
}
