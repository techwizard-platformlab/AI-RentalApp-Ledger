# WAF Policy using Web Application Firewall policy (Standard_v2 tier required for Application Gateway)
# Cost note: WAF policy itself is free; cost comes from the Application Gateway that uses it.
# We use Prevention mode for prod-like enforcement; Detection mode is fine for dev/learning.
resource "azurerm_web_application_firewall_policy" "this" {
  name                = "${var.environment}-${var.location_short}-waf-policy"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = var.waf_mode # "Detection" for dev (no blocked traffic), "Prevention" for qa+
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}
