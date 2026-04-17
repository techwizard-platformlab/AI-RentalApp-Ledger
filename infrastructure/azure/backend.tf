# =============================================================================
# Terraform Azure Remote State Backend
# Values are populated after running bootstrap/azure/bootstrap.sh
# =============================================================================

terraform {
  backend "azurerm" {
    resource_group_name  = "<TF_BACKEND_RG>" # from bootstrap output
    storage_account_name = "<TF_BACKEND_SA>" # from bootstrap output
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
    use_oidc             = true                      # GitHub Actions OIDC auth
    subscription_id      = "<AZURE_SUBSCRIPTION_ID>" # from bootstrap output
    tenant_id            = "<AZURE_TENANT_ID>"       # from bootstrap output
    client_id            = "<AZURE_CLIENT_ID>"       # from bootstrap output
  }
}
