package cost_tfplan

import future.keywords.if
import future.keywords.in

# =============================================================================
# OPA Cost Estimation — Terraform Plan JSON
#
# Input:  terraform show -json tfplan > plan.json
# Usage:  conftest test plan.json --namespace cost_tfplan \
#           --policy platform/security/policies/cost/tf_plan_cost.rego
#
# Cost model: deploy-destroy pattern
#   Compute  → hourly_rate × 88 hrs/month (4 hrs/day × 22 working days)
#   Persistent → full monthly rate (ACR, Key Vault, Storage)
# =============================================================================

compute_hours_per_month := 88

# ── VM / node hourly costs (USD, East US) ────────────────────────────────────
vm_hourly_cost := {
  "standard_b2s":    0.0416,
  "standard_b1ms":   0.0207,
  "standard_b2ms":   0.0832,
  "standard_b4ms":   0.1664,
  "standard_d2s_v3": 0.096,
  "standard_d4s_v3": 0.192,
  "standard_d2s_v4": 0.096,
  "standard_d4s_v4": 0.192,
  "standard_d2s_v5": 0.096,
  "standard_d4s_v5": 0.192,
}

# ── PostgreSQL Flexible Server hourly costs (USD) ────────────────────────────
postgresql_hourly_cost := {
  "b_standard_b1ms":    0.0252,
  "b_standard_b2ms":    0.0504,
  "b_standard_b4ms":    0.1008,
  "gp_standard_d2s_v3": 0.252,
  "gp_standard_d4s_v3": 0.504,
  "gp_standard_d2s_v4": 0.252,
  "gp_standard_d4s_v4": 0.504,
}

# ── Azure SQL Database monthly costs (fixed, USD) ────────────────────────────
sql_monthly_cost := {
  "basic": 4.90,
  "s0":    14.72,
  "s1":    29.44,
  "s2":    58.88,
  "s3":   117.76,
}

# ── Container Registry monthly costs (fixed, USD) ────────────────────────────
acr_monthly_cost := {
  "basic":    5.01,
  "standard": 20.05,
  "premium":  50.13,
}

# ── Thresholds matching cost_guard.rego (USD/month) ──────────────────────────
deny_threshold         := 22
warn_threshold         := 15
per_resource_warn_usd  := 8

# =============================================================================
# Active resource changes — only "create" and "update" actions count
# =============================================================================
active_changes := [rc |
  rc := input.resource_changes[_]
  some action in rc.change.actions
  action in {"create", "update"}
]

# =============================================================================
# Per-resource cost estimation
# Each function returns the estimated monthly USD cost for one resource_change.
# Unknown resource types return 0 (no false positives).
# =============================================================================

# AKS cluster — cost from default_node_pool vm_size × node_count
resource_cost(rc) := cost if {
  rc.type == "azurerm_kubernetes_cluster"
  pool := rc.change.after.default_node_pool[0]
  vm_key := lower(pool.vm_size)
  hourly := vm_hourly_cost[vm_key]
  count := object.get(pool, "node_count", 1)
  cost := hourly * count * compute_hours_per_month
}

# AKS additional node pool (e.g. appnode)
resource_cost(rc) := cost if {
  rc.type == "azurerm_kubernetes_cluster_node_pool"
  vm_key := lower(rc.change.after.vm_size)
  hourly := vm_hourly_cost[vm_key]
  # Use max_count for autoscaled pools, node_count otherwise
  count := object.get(rc.change.after, "max_count",
             object.get(rc.change.after, "node_count", 1))
  cost := hourly * count * compute_hours_per_month
}

# PostgreSQL Flexible Server (compute-hours)
resource_cost(rc) := cost if {
  rc.type == "azurerm_postgresql_flexible_server"
  sku_key := lower(rc.change.after.sku_name)
  hourly := postgresql_hourly_cost[sku_key]
  cost := hourly * compute_hours_per_month
}

# Azure SQL Database (monthly fixed)
resource_cost(rc) := cost if {
  rc.type == "azurerm_mssql_database"
  sku_key := lower(rc.change.after.sku_name)
  cost := sql_monthly_cost[sku_key]
}

# Container Registry (persistent — full month)
resource_cost(rc) := cost if {
  rc.type == "azurerm_container_registry"
  sku_key := lower(rc.change.after.sku)
  cost := acr_monthly_cost[sku_key]
}

# Key Vault (persistent, minimal)
resource_cost(rc) := 1.0 if {
  rc.type == "azurerm_key_vault"
}

# Storage Account (persistent, estimate for tfstate + app blobs)
resource_cost(rc) := 1.5 if {
  rc.type == "azurerm_storage_account"
}

# Public IP (per-hour, compute-hours only)
resource_cost(rc) := cost if {
  rc.type == "azurerm_public_ip"
  cost := 0.004 * compute_hours_per_month
}

# Load Balancer (per-hour)
resource_cost(rc) := cost if {
  rc.type == "azurerm_lb"
  cost := 0.025 * compute_hours_per_month
}

# Default — unknown resource types contribute $0 (no false denials)
resource_cost(rc) := 0 if {
  not rc.type in {
    "azurerm_kubernetes_cluster",
    "azurerm_kubernetes_cluster_node_pool",
    "azurerm_postgresql_flexible_server",
    "azurerm_mssql_database",
    "azurerm_container_registry",
    "azurerm_key_vault",
    "azurerm_storage_account",
    "azurerm_public_ip",
    "azurerm_lb",
  }
}

# =============================================================================
# Aggregate: cost breakdown and total
# =============================================================================
cost_breakdown := [entry |
  rc := active_changes[_]
  cost := resource_cost(rc)
  entry := {
    "address": rc.address,
    "type":    rc.type,
    "cost":    cost,
  }
]

total_estimated_cost := sum([entry.cost | entry := cost_breakdown[_]])

# =============================================================================
# RULE: Deny if total estimated cost exceeds monthly budget
# =============================================================================
deny[msg] if {
  total_estimated_cost > deny_threshold
  top_entries := top3_by_cost
  msg := sprintf(
    "[TF PLAN COST] Estimated monthly cost $%.2f exceeds $%d limit (deploy-destroy, 88 hrs/month).\nTop resources:\n%s\nReduce node sizes, switch to postgresql B_Standard_B1ms, or review replica counts.",
    [total_estimated_cost, deny_threshold, top_entries],
  )
}

# =============================================================================
# RULE: Warn if cost is in amber zone
# =============================================================================
warn[msg] if {
  total_estimated_cost >= warn_threshold
  total_estimated_cost <= deny_threshold
  msg := sprintf(
    "[TF PLAN COST] Estimated monthly cost $%.2f is in warning range ($%d–$%d). Review before applying.",
    [total_estimated_cost, warn_threshold, deny_threshold],
  )
}

# =============================================================================
# RULE: Warn if any single resource exceeds the per-resource threshold
# =============================================================================
warn[msg] if {
  entry := cost_breakdown[_]
  entry.cost > per_resource_warn_usd
  msg := sprintf(
    "[TF PLAN COST] '%s' (%s) estimated at $%.2f/month — exceeds $%d single-resource warning.",
    [entry.address, entry.type, entry.cost, per_resource_warn_usd],
  )
}

# =============================================================================
# Helper: top 3 most expensive resources as formatted string
# =============================================================================
top3_by_cost := result if {
  sorted_desc := reverse_sort([e.cost | e := cost_breakdown[_]])
  top_costs := array.slice(sorted_desc, 0, 3)
  top_entries := [entry |
    entry := cost_breakdown[_]
    entry.cost in top_costs
  ]
  lines := [line |
    e := top_entries[_]
    line := sprintf("  - %s: $%.2f/month", [e.address, e.cost])
  ]
  result := concat("\n", lines)
}

# OPA built-in sort is ascending — reverse for descending
reverse_sort(arr) := result if {
  sorted := sort(arr)
  result := array.reverse(sorted)
}
