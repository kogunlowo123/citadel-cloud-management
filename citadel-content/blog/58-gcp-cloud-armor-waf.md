# GCP Cloud Armor: WAF and DDoS Protection with Terraform

**Pillar:** GCP Infrastructure
**SEO Target:** gcp cloud armor terraform waf ddos owasp security policies rules
**Word Count:** ~1400

Cloud Armor protects GCP load balancers with WAF rules, DDoS mitigation, and rate limiting. This guide deploys production Cloud Armor security policies with OWASP CRS rules using Terraform.

## Security Policy

```hcl
resource "google_compute_security_policy" "main" {
  name        = "${var.prefix}-security-policy"
  description = "Production WAF policy with OWASP CRS"
  project     = var.project_id

  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
    description = "Block SQL injection"
  }

  rule {
    action   = "deny(403)"
    priority = "1001"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "Block XSS"
  }

  rule {
    action   = "deny(403)"
    priority = "1002"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-v33-stable') || evaluatePreconfiguredExpr('rfi-v33-stable')"
      }
    }
    description = "Block LFI/RFI"
  }

  rule {
    action   = "throttle"
    priority = "2000"
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
    }
    description = "Rate limit: 100 req/min per IP"
  }

  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config { src_ip_ranges = ["*"] }
    }
    description = "Default allow"
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "STANDARD"
    }
  }
}
```

## Backend Service Association

```hcl
resource "google_compute_backend_service" "main" {
  name                  = "${var.prefix}-backend"
  project               = var.project_id
  security_policy       = google_compute_security_policy.main.self_link
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
```

## Production Checklist
- [ ] OWASP CRS v3.3 stable rules (sqli, xss, lfi, rfi, rce)
- [ ] Rate limiting: 100 req/min per IP (adjust per traffic patterns)
- [ ] Adaptive Protection Layer 7 DDoS defense enabled
- [ ] Named IP address groups for allowlisted partners
- [ ] Cloud Armor Managed Protection Plus for advanced threat intelligence
- [ ] Logging enabled: sampled requests for tuning false positives