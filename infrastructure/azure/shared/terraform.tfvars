location       = "eastus"
location_short = "eus"
project        = "rentalAppLedger"
acr_sku        = "Basic"

# Injected via TF_VAR_* in CI:
#   TF_VAR_subscription_id            → AZURE_SUBSCRIPTION_ID
#   TF_VAR_shared_resource_group_name → TF_SHARED_RG
#   TF_VAR_github_actions_principal_id → AZURE_CLIENT_OBJECT_ID
