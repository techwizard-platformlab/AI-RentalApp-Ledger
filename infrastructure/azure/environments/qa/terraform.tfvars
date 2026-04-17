# =============================================================================
# Azure qa — non-secret environment config
# Committed to git. Secrets injected by GitHub Actions as TF_VAR_* env vars:
#   TF_VAR_subscription_id             → AZURE_SUBSCRIPTION_ID
#   TF_VAR_env_resource_group_name     → resolved from setup job (my-Rental-App-QA)
#   TF_VAR_shared_resource_group_name  → TF_SHARED_RG
#   TF_VAR_acr_name                    → ACR_NAME (from shared/ outputs)
#   TF_VAR_github_actions_principal_id → AZURE_CLIENT_OBJECT_ID
# =============================================================================

# ── Environment identity ──────────────────────────────────────────────────────
environment    = "qa"
location       = "eastus2"
location_short = "eus2"
project        = "rentalAppLedger"
owner          = "techwizard-platformlab"

# ── Networking ────────────────────────────────────────────────────────────────
vnet_cidr    = "10.1.0.0/16"
subnet_cidrs = { aks = "10.1.1.0/24", ingress = "10.1.2.0/24", data = "10.1.3.0/24" }

# ── Compute ───────────────────────────────────────────────────────────────────
aks_node_count = 1
aks_vm_size    = "Standard_B2s"
aks_os_disk_gb = 30

# ── Database engine ───────────────────────────────────────────────────────────
db_engine = "postgresql"

# ── PostgreSQL Flexible Server (active when db_engine = "postgresql") ─────────
postgresql_sku          = "B_Standard_B1ms"
postgresql_storage_mb   = 32768 # 32 GiB minimum
postgresql_storage_tier = "P4"

# ── Azure SQL Database (active when db_engine = "mssql") ─────────────────────
# S1 — 20 DTUs for QA load tests, ~$15/month
mssql_sku         = "S1"
mssql_max_size_gb = 10

# ── Storage ───────────────────────────────────────────────────────────────────
app_storage_containers = ["uploads", "backups"]

# ── Cost management ───────────────────────────────────────────────────────────
monthly_budget_usd = 22
budget_start_date  = "2026-04-01T00:00:00Z"
alert_emails       = ["ramprasath2691@outlook.com"]
