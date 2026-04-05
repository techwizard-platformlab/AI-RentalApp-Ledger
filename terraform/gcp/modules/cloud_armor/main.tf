# Cloud Armor security policy — GCP's WAF equivalent
# Cost note: Cloud Armor standard is ~$5/policy/month + $1/million requests.
# Preconfigured OWASP rules are included in the standard tier.
resource "google_compute_security_policy" "this" {
  name    = "${var.environment}-${var.region_short}-armor-policy"
  project = var.project_id

  # Default rule: allow all traffic (explicit deny rules below will override)
  rule {
    action   = "allow"
    priority = "2147483647"  # lowest priority = default
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }

  # OWASP Core Rule Set — XSS
  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
    description = "Block XSS attacks (OWASP CRS)"
  }

  # OWASP Core Rule Set — SQL injection
  rule {
    action   = "deny(403)"
    priority = "1001"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
    description = "Block SQL injection (OWASP CRS)"
  }

  # OWASP Core Rule Set — Remote/Local File Inclusion
  rule {
    action   = "deny(403)"
    priority = "1002"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rfi-stable')"
      }
    }
    description = "Block RFI attacks (OWASP CRS)"
  }

  # Rate limiting — 100 req/min per IP to mitigate brute force / scraping
  rule {
    action   = "throttle"
    priority = "500"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      enforce_on_key = "IP"
    }
    description = "Rate limit: 100 req/min per IP"
  }
}
