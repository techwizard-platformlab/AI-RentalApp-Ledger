# Azure Consumption Budget — Resource Group scope
# Sends email alerts when weekly spend approaches or exceeds the configured limit.
# Default: $5/week (~420 INR) with alerts at 70%, 90%, and 100%.

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

resource "azurerm_consumption_budget_resource_group" "weekly" {
  name              = "${var.environment}-weekly-budget"
  resource_group_id = data.azurerm_resource_group.this.id

  amount     = var.weekly_budget_usd
  time_grain = "Weekly"

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
