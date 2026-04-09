data "azuread_client_config" "current" {}

# App Registration for a workload identity (no client secret — OIDC only)
resource "azuread_application" "this" {
  display_name = "${var.environment}-${var.app_name}"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "this" {
  client_id = azuread_application.this.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Federated credential for GitHub Actions OIDC (main branch)
resource "azuread_application_federated_identity_credential" "github_main" {
  application_id = azuread_application.this.id
  display_name   = "github-main"
  description    = "GitHub Actions OIDC — main branch"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
}

# Federated credential for pull requests
resource "azuread_application_federated_identity_credential" "github_pr" {
  application_id = azuread_application.this.id
  display_name   = "github-pr"
  description    = "GitHub Actions OIDC — pull requests"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:pull_request"
}

# Role assignment scoped to the existing Resource Group
resource "azurerm_role_assignment" "rg_contributor" {
  scope                = var.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.this.object_id
}
