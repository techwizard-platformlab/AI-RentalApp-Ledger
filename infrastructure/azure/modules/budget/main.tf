# Azure Consumption Budget — Resource Group scope
# Sends email alerts when monthly spend approaches or exceeds the configured limit.
# Default: $22/month (~1840 INR) = $5/week × 4.33 weeks, with alerts at 70%, 90%, and 100%.
#
# resource_group_id is passed directly from the caller (azurerm_resource_group.env.id)
# so this module does not need a data source lookup — safe to apply even on first run.
#
# If alert_emails is empty, notifications fall back to the subscription Owner role
# so the budget resource is never rejected by Azure for having empty contacts.

locals {
  emails        = length(var.alert_emails) > 0 ? var.alert_emails : []
  contact_roles = length(var.alert_emails) > 0 ? [] : ["Owner"]
}

resource "azurerm_consumption_budget_resource_group" "monthly" {
  name              = "${var.environment}-monthly-budget"
  resource_group_id = var.resource_group_id

  amount     = var.monthly_budget_usd
  time_grain = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 70
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = local.emails
    contact_roles  = local.contact_roles
  }

  notification {
    enabled        = true
    threshold      = 90
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = local.emails
    contact_roles  = local.contact_roles
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = local.emails
    contact_roles  = local.contact_roles
  }

  notification {
    enabled        = true
    threshold      = 110
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = local.emails
    contact_roles  = local.contact_roles
  }
}
