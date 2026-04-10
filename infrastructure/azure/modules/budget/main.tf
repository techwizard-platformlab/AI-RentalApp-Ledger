# Azure Consumption Budget — Resource Group scope
# Sends email alerts when monthly spend approaches or exceeds the configured limit.
# Default: $22/month (~1840 INR) = $5/week × 4.33 weeks, with alerts at 70%, 90%, and 100%.

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

resource "azurerm_consumption_budget_resource_group" "monthly" {
  name              = "${var.environment}-monthly-budget"
  resource_group_id = data.azurerm_resource_group.this.id

  amount     = var.monthly_budget_usd
  time_grain = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  # Alert at 70% — early warning
  notification {
    enabled        = true
    threshold      = 70
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.alert_emails
  }

  # Alert at 90% — approaching limit
  notification {
    enabled        = true
    threshold      = 90
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.alert_emails
  }

  # Alert at 100% — limit reached
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.alert_emails
  }

  # Forecast alert — warns before the budget is actually exceeded
  notification {
    enabled        = true
    threshold      = 110
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.alert_emails
  }
}
