# Protecting Your AWS Applications with WAFv2: Managed Rules, Rate Limiting, and Bot Control

> **Header Image Suggestion:** A shield icon in front of an AWS CloudFront/ALB architecture, with incoming traffic arrows being filtered through WAF rule layers — showing allowed (green) and blocked (red) requests.

**Tags:** `#aws` `#security` `#terraform` `#webdev` `#devops`

---

Your application is live. Traffic is flowing. And somewhere on the internet, an automated scanner is already probing your endpoints for SQL injection vulnerabilities, while a botnet prepares a credential stuffing attack against your login page.

AWS WAFv2 sits between your users and your application, inspecting every HTTP request against a set of rules you define. Done well, it blocks the vast majority of automated attacks without your application code knowing anything happened. Done poorly, it gives you a false sense of security or blocks legitimate users.

This article covers how to configure WAFv2 properly using Terraform, based on patterns from my [terraform-aws-waf](https://github.com/kogunlowo123/terraform-aws-waf) module.

## Where WAF Fits in Your Security Stack

WAF is not a replacement for secure application code. It's a layer of defense that catches common attack patterns before they reach your application:

```
Internet → CloudFront/ALB → WAFv2 → Your Application
                              ↓
                         Block/Allow/Count
                              ↓
                     CloudWatch + S3 Logs
```

Think of it as a bouncer at the door. The bouncer catches obviously problematic behavior (fake IDs, weapons), but your application still needs to validate inputs, authenticate users, and handle authorization properly.

## Attack Patterns WAF Catches

Before diving into configuration, let's understand what we're defending against:

| Attack | How It Works | WAF Mitigation |
|--------|-------------|----------------|
| **SQL Injection** | Malicious SQL in form fields/parameters | SQLi rule group inspects body/query strings |
| **Cross-Site Scripting** | JavaScript injection via user input | XSS rule group pattern matching |
| **Path Traversal** | `../../etc/passwd` in URLs | Known bad input rules |
| **Credential Stuffing** | Automated login attempts with stolen credentials | Rate limiting on login endpoints |
| **DDoS (Layer 7)** | Overwhelming request volume | Rate-based rules + Shield |
| **Bad Bots** | Scrapers, scanners, exploit kits | Bot Control managed rule group |
| **Log4Shell/Known CVEs** | Exploit strings in headers/body | Known exploits rule group |

## Setting Up WAFv2 with Terraform

Here's a production configuration using the [terraform-aws-waf](https://github.com/kogunlowo123/terraform-aws-waf) module:

```hcl
module "waf" {
  source = "github.com/kogunlowo123/terraform-aws-waf"

  waf_name    = "production-web-acl"
  description = "Production WAF for customer-facing applications"
  scope       = "REGIONAL"  # Use "CLOUDFRONT" for CloudFront distributions

  # Default action — allow everything that doesn't match a rule
  default_action = "allow"

  # Associate with ALB
  resource_arns = [
    aws_lb.application.arn
  ]

  # Logging
  enable_logging         = true
  log_destination_arn    = aws_kinesis_firehose_delivery_stream.waf_logs.arn
  redacted_fields        = ["authorization", "cookie"]

  tags = {
    Environment = "production"
    Service     = "customer-portal"
  }
}
```

The `scope` parameter is important. `REGIONAL` WAFs attach to ALBs, API Gateways, and AppSync APIs. `CLOUDFRONT` WAFs must be created in `us-east-1` and attach to CloudFront distributions.

## Rule Group Strategy

Rules are evaluated in priority order (lowest number first). If a rule matches, its action is taken and evaluation stops. This ordering matters:

```hcl
module "waf" {
  source = "github.com/kogunlowo123/terraform-aws-waf"

  # ... base config ...

  rule_groups = [

    # Priority 1: Allow known good traffic (IP allowlist)
    {
      name     = "allow-internal-ips"
      priority = 1
      action   = "allow"
      type     = "ip_set"
      ip_set = {
        name           = "internal-ips"
        addresses      = ["203.0.113.0/24", "198.51.100.0/24"]
        ip_address_version = "IPV4"
      }
    },

    # Priority 2: Block known bad IPs
    {
      name     = "block-malicious-ips"
      priority = 2
      action   = "block"
      type     = "ip_set"
      ip_set = {
        name           = "blocked-ips"
        addresses      = []  # Managed via API/Lambda
        ip_address_version = "IPV4"
      }
    },

    # Priority 10: Rate limiting
    {
      name     = "rate-limit-global"
      priority = 10
      action   = "block"
      type     = "rate_based"
      rate_based = {
        limit              = 2000  # requests per 5-minute window
        aggregate_key_type = "IP"
      }
    },

    # Priority 20: AWS Managed Rules - Common
    {
      name     = "aws-common-rules"
      priority = 20
      type     = "managed"
      managed_rule_group = {
        vendor = "AWS"
        name   = "AWSManagedRulesCommonRuleSet"
      }
      override_action = "none"  # Use the rule group's actions
    },

    # Priority 30: AWS Managed Rules - SQL Injection
    {
      name     = "aws-sqli-rules"
      priority = 30
      type     = "managed"
      managed_rule_group = {
        vendor = "AWS"
        name   = "AWSManagedRulesSQLiRuleSet"
      }
      override_action = "none"
    },

    # Priority 40: AWS Managed Rules - Known Bad Inputs
    {
      name     = "aws-known-bad-inputs"
      priority = 40
      type     = "managed"
      managed_rule_group = {
        vendor = "AWS"
        name   = "AWSManagedRulesKnownBadInputsRuleSet"
      }
      override_action = "none"
    },

    # Priority 50: AWS Managed Rules - Linux OS
    {
      name     = "aws-linux-rules"
      priority = 50
      type     = "managed"
      managed_rule_group = {
        vendor = "AWS"
        name   = "AWSManagedRulesLinuxRuleSet"
      }
      override_action = "none"
    },

    # Priority 60: Bot Control
    {
      name     = "aws-bot-control"
      priority = 60
      type     = "managed"
      managed_rule_group = {
        vendor = "AWS"
        name   = "AWSManagedRulesBotControlRuleSet"
        managed_rule_group_configs = [
          {
            aws_managed_rules_bot_control_rule_set = {
              inspection_level = "COMMON"
            }
          }
        ]
      }
      override_action = "none"
    }
  ]
}
```

### Why This Order Matters

1. **IP allowlists first** (priority 1) — internal monitoring, health checks, and known partner IPs bypass all other rules. This prevents false positives on legitimate traffic.

2. **IP blocklists second** (priority 2) — known bad actors are blocked immediately, saving WAF capacity units on rule evaluation.

3. **Rate limiting** (priority 10) — catches volumetric attacks before expensive managed rule evaluation.

4. **Managed rules** (priority 20-60) — the heavy lifting. AWS maintains these rules and updates them as new attack patterns emerge.

## Rate Limiting: Beyond Simple Thresholds

A global rate limit is a starting point, but production workloads need targeted rate limiting:

```hcl
# Aggressive rate limiting on authentication endpoints
{
  name     = "rate-limit-login"
  priority = 11
  action   = "block"
  type     = "rate_based"
  rate_based = {
    limit              = 100  # 100 requests per 5 minutes per IP
    aggregate_key_type = "IP"
    scope_down_statement = {
      type = "byte_match"
      byte_match = {
        search_string         = "/api/auth/login"
        field_to_match        = "uri_path"
        positional_constraint = "STARTS_WITH"
        text_transformations  = [{ priority = 0, type = "LOWERCASE" }]
      }
    }
  }
}

# Rate limiting on API endpoints by IP + API key
{
  name     = "rate-limit-api"
  priority = 12
  action   = "block"
  type     = "rate_based"
  rate_based = {
    limit              = 500
    aggregate_key_type = "CUSTOM_KEYS"
    custom_keys = [
      { type = "ip" },
      {
        type = "header"
        header = {
          name = "x-api-key"
          text_transformations = [{ priority = 0, type = "NONE" }]
        }
      }
    ]
  }
}
```

The login endpoint gets 100 requests per 5 minutes per IP. That's generous for legitimate users (who typically log in once) but blocks credential stuffing attacks that send thousands of requests.

## Bot Control: Separating Good Bots from Bad

Not all bots are bad. Googlebot, monitoring services, and partner integrations are legitimate. The Bot Control managed rule group categorizes bots and lets you handle each category differently:

```hcl
# Custom bot handling
{
  name     = "bot-control-custom"
  priority = 55
  type     = "managed"
  managed_rule_group = {
    vendor = "AWS"
    name   = "AWSManagedRulesBotControlRuleSet"
    managed_rule_group_configs = [
      {
        aws_managed_rules_bot_control_rule_set = {
          inspection_level = "TARGETED"  # More aggressive detection
        }
      }
    ]
    # Override specific rules within the group
    rule_action_overrides = [
      {
        # Allow verified search engine bots
        name          = "CategorySearchEngine"
        action_to_use = "allow"
      },
      {
        # Challenge unverified bots instead of blocking
        name          = "SignalNonBrowserUserAgent"
        action_to_use = "captcha"
      },
      {
        # Block automated frameworks
        name          = "CategoryHttpLibrary"
        action_to_use = "block"
      }
    ]
  }
}
```

The `TARGETED` inspection level uses machine learning to detect sophisticated bots that mimic browser behavior. It's more expensive but catches bots that `COMMON` inspection misses.

## Custom Rules for Application-Specific Protection

Managed rules handle generic attacks, but your application has unique endpoints that need custom protection:

```hcl
# Block requests with suspiciously large bodies on specific endpoints
custom_rules = [
  {
    name     = "block-large-upload-non-upload-endpoints"
    priority = 15
    action   = "block"
    statement = {
      type = "and"
      statements = [
        {
          type = "not"
          statement = {
            type = "byte_match"
            byte_match = {
              search_string         = "/api/uploads"
              field_to_match        = "uri_path"
              positional_constraint = "STARTS_WITH"
              text_transformations  = [{ priority = 0, type = "LOWERCASE" }]
            }
          }
        },
        {
          type = "size_constraint"
          size_constraint = {
            field_to_match       = "body"
            comparison_operator  = "GT"
            size                 = 8192  # 8KB
            text_transformations = [{ priority = 0, type = "NONE" }]
          }
        }
      ]
    }
  },

  # Geo-blocking (if required by compliance)
  {
    name     = "geo-restrict"
    priority = 5
    action   = "block"
    statement = {
      type = "geo_match"
      geo_match = {
        country_codes = ["KP", "IR", "SY", "CU"]  # Sanctioned countries
      }
    }
  }
]
```

## Logging and Monitoring

WAF logs are verbose — every evaluated request generates a log entry. You need a strategy for managing this volume:

```hcl
# WAF logging via Kinesis Firehose to S3
resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  name        = "aws-waf-logs-production"  # Must start with "aws-waf-logs-"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.waf_logs.arn

    prefix              = "waf-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "waf-logs-errors/"

    buffering_size     = 128  # MB
    buffering_interval = 300  # seconds

    compression_format = "GZIP"
  }
}
```

### CloudWatch Metrics and Alarms

```hcl
# Alert on high block rate
resource "aws_cloudwatch_metric_alarm" "waf_high_block_rate" {
  alarm_name          = "waf-high-block-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 1000

  metric_query {
    id          = "blocked"
    return_data = true
    metric {
      metric_name = "BlockedRequests"
      namespace   = "AWS/WAFV2"
      period      = 300
      stat        = "Sum"
      dimensions = {
        WebACL = "production-web-acl"
        Rule   = "ALL"
        Region = "eu-west-1"
      }
    }
  }

  alarm_actions = [aws_sns_topic.security_alerts.arn]
}
```

A sudden spike in blocked requests might mean you're under attack (good — WAF is working) or a rule is incorrectly blocking legitimate traffic (bad — investigate immediately).

### Analyzing WAF Logs with Athena

```sql
-- Top blocked requests by rule group
SELECT
  terminatingRuleId,
  action,
  COUNT(*) as request_count,
  COUNT(DISTINCT httpRequest.clientIp) as unique_ips
FROM waf_logs
WHERE action = 'BLOCK'
  AND date_partition = '2026/03/06'
GROUP BY terminatingRuleId, action
ORDER BY request_count DESC;

-- Find potential false positives
SELECT
  httpRequest.uri,
  httpRequest.clientIp,
  httpRequest.country,
  terminatingRuleId,
  terminatingRuleMatchDetails
FROM waf_logs
WHERE action = 'BLOCK'
  AND terminatingRuleId = 'AWS-AWSManagedRulesCommonRuleSet'
  AND httpRequest.country = 'GB'
ORDER BY timestamp DESC
LIMIT 50;
```

## Cost Considerations

WAF pricing has three components:

| Component | Cost | Notes |
|-----------|------|-------|
| Web ACL | $5/month | Per Web ACL |
| Rules | $1/month per rule | Managed rule groups count as 1 rule |
| Requests | $0.60 per million | All requests, not just blocked |
| Bot Control (Common) | $10/month + $1/million requests | Adds to base cost |
| Bot Control (Targeted) | $10/month + $10/million requests | Significantly more expensive |

For a typical production setup with 5 managed rule groups, 3 custom rules, and 50 million requests/month:

- Web ACL: $5
- Rules: $8 (5 managed + 3 custom)
- Requests: $30
- **Total: ~$43/month**

Adding Bot Control (Targeted) at 50 million requests: $10 + $500 = **$510/month additional**. That's a significant jump. Start with Common inspection and upgrade to Targeted only for endpoints where sophisticated bot detection justifies the cost.

## Deployment Strategy: Count Before Block

Never deploy WAF rules in block mode on day one. Always follow this progression:

1. **Count mode** — rules evaluate but don't block. Monitor for 1-2 weeks.
2. **Review logs** — identify false positives and create exceptions.
3. **Block mode** — switch rules to blocking after confirming no legitimate traffic is affected.

```hcl
# Start in count mode
override_action = "count"  # Evaluate but don't block

# After validation, switch to enforcement
# override_action = "none"  # Use the rule group's native actions
```

This approach prevents the "we deployed WAF and broke production" scenario that gives WAFs a bad reputation.

## Wrapping Up

WAFv2 is one of the highest-value security controls you can deploy on AWS. For roughly the cost of a developer's daily coffee, you get protection against the most common web attack patterns.

The key takeaways:

1. **Layer your rules** — IP allowlists, rate limits, managed rules, custom rules, in that order
2. **Start in count mode** — validate before you block
3. **Log everything** — you can't tune what you can't see
4. **Rate limit aggressively on auth endpoints** — this is where attacks concentrate
5. **Budget for Bot Control** — the cost can surprise you at scale

The complete module with all patterns discussed here:

- [terraform-aws-waf](https://github.com/kogunlowo123/terraform-aws-waf) — Production WAFv2 module with managed rules, rate limiting, and bot control

Check out the rest of my infrastructure modules at [github.com/kogunlowo123](https://github.com/kogunlowo123), including the [terraform-aws-vpc-complete](https://github.com/kogunlowo123/terraform-aws-vpc-complete) module for the underlying network architecture.

---

*Dealing with a specific attack pattern that WAF doesn't catch out of the box? Share it in the comments — I've probably written a custom rule for it.*
