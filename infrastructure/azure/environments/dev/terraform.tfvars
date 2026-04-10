# =============================================================================
# Azure dev — non-secret environment config
# Committed to git. Secrets injected by GitHub Actions as TF_VAR_* env vars:
#   TF_VAR_subscription_id            → AZURE_SUBSCRIPTION_ID
#   TF_VAR_env_resource_group_name    → resolved from setup job (my-Rental-App-Dev)
#   TF_VAR_shared_resource_group_name → TF_SHARED_RG
#   TF_VAR_acr_name                   → ACR_NAME
#   TF_VAR_key_vault_name             → KEY_VAULT_NAME
# =============================================================================

environment = "dev"
location    = "eastus"

# ── Database engine ───────────────────────────────────────────────────────────
# Options: "postgresql" (default) | "mssql"
# To switch to Azure SQL, change db_engine to "mssql" — only that module deploys.
db_engine = "mssql"

# ── PostgreSQL Flexible Server (active when db_engine = "postgresql") ─────────
# B_Standard_B1ms — 1 vCore Burstable, ~$12/month
postgresql_sku          = "B_Standard_B1ms"
postgresql_storage_mb   = 32768   # 32 GiB minimum
postgresql_storage_tier = "P4"

# ── Azure SQL Database (active when db_engine = "mssql") ─────────────────────
# Basic — 5 DTUs, ~$5/month
mssql_sku         = "Basic"
mssql_max_size_gb = 2
