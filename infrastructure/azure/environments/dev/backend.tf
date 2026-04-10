terraform {
  backend "azurerm" {
    resource_group_name  = "my-Rental-App"
    storage_account_name = "rentalledgertf8d76e26a"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
    use_oidc             = true
  }
}
