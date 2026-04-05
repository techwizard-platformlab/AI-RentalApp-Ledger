package cost

import future.keywords.if
import future.keywords.every

# ─────────────────────────────────────────────────────────────────────────────
# Thresholds (USD / month) — playground safety guards
# ─────────────────────────────────────────────────────────────────────────────
deny_threshold  := 30    # hard block
amber_threshold := 20    # warn zone: 20-30 USD
per_resource_warn_threshold := 10
aks_monthly_limit := 15

# ─────────────────────────────────────────────────────────────────────────────
# Parse infracost JSON: total cost
# Input: infracost breakdown --format json | ...
# ─────────────────────────────────────────────────────────────────────────────
total_monthly_cost := sum([cost |
  project := input.projects[_]
  cost_str := project.breakdown.totalMonthlyCost
  cost := to_number(cost_str)
])

# All resources with their costs
all_resources := [res |
  project := input.projects[_]
  res := project.breakdown.resources[_]
]

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny if total monthly cost > $30
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] if {
  total_monthly_cost > deny_threshold
  top3 := top_3_expensive
  msg := sprintf(
    "[COST HARD LIMIT] Total estimated monthly cost $%.2f exceeds playground limit of $%d.\nTop 3 most expensive resources:\n%s",
    [total_monthly_cost, deny_threshold, top3]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Warn if cost in amber zone ($20–$30)
# ─────────────────────────────────────────────────────────────────────────────
warn[msg] if {
  total_monthly_cost >= amber_threshold
  total_monthly_cost <= deny_threshold
  msg := sprintf(
    "[COST AMBER ZONE] Estimated monthly cost $%.2f is in the warning range ($%d–$%d). Review before applying.",
    [total_monthly_cost, amber_threshold, deny_threshold]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Warn if any single resource > $10/month
# ─────────────────────────────────────────────────────────────────────────────
warn[msg] if {
  res := all_resources[_]
  res_cost := to_number(object.get(res, "monthlyCost", "0"))
  res_cost > per_resource_warn_threshold
  msg := sprintf(
    "[RESOURCE COST] '%s' (%s) costs $%.2f/month — exceeds $%d single-resource warning threshold.",
    [res.name, object.get(res, "resourceType", "unknown"), res_cost, per_resource_warn_threshold]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny if AKS monthly estimate > $15 (B2s baseline)
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] if {
  res := all_resources[_]
  contains(lower(res.name), "kubernetes")
  res_cost := to_number(object.get(res, "monthlyCost", "0"))
  res_cost > aks_monthly_limit
  msg := sprintf(
    "[AKS COST] AKS resource '%s' estimated at $%.2f/month exceeds $%d B2s baseline. Check node count and VM size.",
    [res.name, res_cost, aks_monthly_limit]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: top 3 most expensive resources formatted for violation message
# ─────────────────────────────────────────────────────────────────────────────
top_3_expensive := result if {
  sorted := sort([cost_pair |
    res := all_resources[_]
    cost_val := to_number(object.get(res, "monthlyCost", "0"))
    cost_pair := {"cost": cost_val, "name": res.name}
  ])
  top3 := array.slice(array.reverse(sorted), 0, 3)
  lines := [line |
    item := top3[_]
    line := sprintf("  - %s: $%.2f/month", [item.name, item.cost])
  ]
  result := concat("\n", lines)
}
