package cost

import future.keywords.if
import future.keywords.every

# ─────────────────────────────────────────────────────────────────────────────
# Cost thresholds (USD / month)
# ─────────────────────────────────────────────────────────────────────────────
warn_threshold := 50
deny_threshold := 100

# ─────────────────────────────────────────────────────────────────────────────
# Input: infracost JSON output
# infracost breakdown --format json | conftest test --input json -p policy/cost/
# ─────────────────────────────────────────────────────────────────────────────

# Total monthly cost across all projects
total_monthly_cost := sum([cost |
  project := input.projects[_]
  cost_str := project.breakdown.totalMonthlyCost
  cost := to_number(cost_str)
])

# ─────────────────────────────────────────────────────────────────────────────
# Rule: Deny if total cost exceeds hard limit
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] if {
  total_monthly_cost > deny_threshold
  msg := sprintf(
    "Estimated monthly cost $%.2f exceeds hard limit of $%d. Deployment blocked.",
    [total_monthly_cost, deny_threshold]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule: Warn if total cost exceeds soft limit (non-blocking)
# ─────────────────────────────────────────────────────────────────────────────
warn[msg] if {
  total_monthly_cost > warn_threshold
  total_monthly_cost <= deny_threshold
  msg := sprintf(
    "WARNING: Estimated monthly cost $%.2f exceeds warning threshold of $%d. Review resources.",
    [total_monthly_cost, warn_threshold]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Cost breakdown per resource (informational - surfaces in PR comment)
# ─────────────────────────────────────────────────────────────────────────────
resource_cost_breakdown[entry] {
  project := input.projects[_]
  resource := project.breakdown.resources[_]
  entry := {
    "name": resource.name,
    "type": resource.resourceType,
    "monthly_cost": resource.monthlyCost,
  }
}
