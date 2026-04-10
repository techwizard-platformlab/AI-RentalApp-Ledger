variable "environment" {
  description = "Environment name (dev, qa)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group to apply the budget to"
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly spend limit in USD. Default $22 ≈ 1840 INR ($5/week × 4.33 weeks). Adjust for exchange rate."
  type        = number
  default     = 22
}

variable "budget_start_date" {
  description = "Budget start date in RFC3339 format (first day of current month)"
  type        = string
  default     = "2026-04-01T00:00:00Z"
}

variable "alert_emails" {
  description = "List of email addresses to notify when budget thresholds are breached"
  type        = list(string)
}
