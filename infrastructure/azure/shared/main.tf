# =============================================================================
# Shared Azure infrastructure — applied ONCE, rarely changed.
# Contains:
#   ACR — single shared registry; images promoted dev → qa by tag
#
# Does NOT contain:
#   Key Vault  — each environment manages its own (see environments/)
#   Storage Account — Terraform state backend is bootstrap-created (see bootstrap/)
#
# Apply:
#   cd infrastructure/azure/shared
#   terraform init -backend-config=...
#   terraform apply
# =============================================================================

locals {
  tags = {
    project = var.project
    tier    = "shared"
    managed = "terraform"
  }
}

# ── ACR — shared container registry ──────────────────────────────────────────
resource "random_string" "acr_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_container_registry" "shared" {
  name                = "rental${var.location_short}acr${random_string.acr_suffix.result}"
  location            = var.location
  resource_group_name = var.shared_resource_group_name
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = local.tags
}

# AcrPush — GitHub Actions CI/CD can push images to the shared registry
resource "azurerm_role_assignment" "github_acr_push" {
  scope                = azurerm_container_registry.shared.id
  role_definition_name = "AcrPush"
  principal_id         = var.github_actions_principal_id
}
