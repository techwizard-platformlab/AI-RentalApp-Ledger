terraform {
  backend "azurerm" {
    resource_group_name  = "<TF_BACKEND_RG>"
    storage_account_name = "<TF_BACKEND_SA>"
    container_name       = "tfstate"
    key                  = "qa.terraform.tfstate"
    use_oidc             = true
  }
}
