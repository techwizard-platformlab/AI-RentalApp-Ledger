# =============================================================================
# Azure qa — non-secret environment config
# Committed to git. Secrets are injected by GitHub Actions as TF_VAR_* env vars:
#   TF_VAR_resource_group_name  → GitHub Secret: AZURE_RESOURCE_GROUP
# =============================================================================

environment = "qa"
location    = "eastus"
