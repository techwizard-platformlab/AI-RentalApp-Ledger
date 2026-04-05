package pr

import future.keywords.if
import future.keywords.in

# ─────────────────────────────────────────────────────────────────────────────
# Input schema (passed via --data or stdin):
# {
#   "unformatted_files": ["terraform/azure/environments/dev/main.tf"],
#   "changelog_updated": true,
#   "qa_plan_exists": false,
#   "changed_paths": ["terraform/azure/environments/dev/main.tf"]
# }
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Rule 1: Deny merge if terraform fmt was not run (unformatted files present)
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] if {
  count(input.unformatted_files) > 0
  msg := sprintf(
    "PR blocked: %d Terraform file(s) are not formatted. Run 'terraform fmt -recursive'. Files: %v",
    [count(input.unformatted_files), input.unformatted_files]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 2: Deny merge if CHANGELOG not updated for infra changes
# ─────────────────────────────────────────────────────────────────────────────
infra_changed if {
  path := input.changed_paths[_]
  startswith(path, "terraform/")
}

deny[msg] if {
  infra_changed
  input.changelog_updated != true
  msg := "PR blocked: Infrastructure files changed but CHANGELOG.md was not updated. Add an entry under [Unreleased]."
}

# ─────────────────────────────────────────────────────────────────────────────
# Rule 3: Warn if no QA environment plan exists for infra changes
# ─────────────────────────────────────────────────────────────────────────────
warn[msg] if {
  infra_changed
  input.qa_plan_exists != true
  msg := "WARNING: Infrastructure changed but no corresponding QA environment plan found. Consider running 'terraform plan' against the QA environment."
}
