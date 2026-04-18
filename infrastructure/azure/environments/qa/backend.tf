terraform {
  backend "azurerm" {
    # All values injected at runtime via terraform init -backend-config in CI:
    #   resource_group_name  = TF_BACKEND_RG  (techwizard-platformlab-apps)
    #   storage_account_name = TF_BACKEND_SA  (techwizardappstfstate)
    #   container_name       = rentalapp-qa-tfstate
    key              = "terraform.tfstate"
    use_oidc         = true
    use_azuread_auth = true
  }
}
