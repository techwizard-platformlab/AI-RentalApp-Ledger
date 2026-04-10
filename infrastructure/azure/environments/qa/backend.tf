terraform {
  backend "azurerm" {
    key      = "qa.terraform.tfstate"
    use_oidc = true
  }
}
