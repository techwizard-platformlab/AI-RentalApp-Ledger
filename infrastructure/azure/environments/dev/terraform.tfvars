# =============================================================================
# Azure dev — non-secret environment config
# Committed to git. Secrets injected by GitHub Actions as TF_VAR_* env vars:
#   TF_VAR_subscription_id             → AZURE_SUBSCRIPTION_ID
#   TF_VAR_env_resource_group_name     → resolved from setup job (my-Rental-App-Dev)
#   TF_VAR_shared_resource_group_name  → TF_SHARED_RG
#   TF_VAR_acr_name                    → ACR_NAME (from shared/ outputs)
#   TF_VAR_github_actions_principal_id → AZURE_CLIENT_OBJECT_ID
# =============================================================================

environment = "dev"
location    = "eastus2"

# ── Database engine ───────────────────────────────────────────────────────────
db_engine = "postgresql"

# ── PostgreSQL Flexible Server (active when db_engine = "postgresql") ─────────
postgresql_sku          = "B_Standard_B1ms"
postgresql_storage_mb   = 32768 # 32 GiB minimum
postgresql_storage_tier = "P4"

# ── Azure SQL Database (active when db_engine = "mssql") ─────────────────────
mssql_sku         = "Basic"
mssql_max_size_gb = 2

# ── Budget alerts ─────────────────────────────────────────────────────────────
alert_emails = ["ramprasath2691@outlook.com"]
