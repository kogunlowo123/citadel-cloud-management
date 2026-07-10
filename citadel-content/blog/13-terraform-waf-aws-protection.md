# AWS WAF v2 with Terraform: Rate Limiting, Bot Control, and Custom Rules

**Pillar:** AWS Infrastructure / DevSecOps
**SEO Target:** "aws waf terraform", "terraform aws waf v2 rate limiting"
**Word Count:** ~1,900

---

AWS WAF v2 is one of the most underutilized security tools in the AWS ecosystem. It's inexpensive, deeply integrated with CloudFront and ALB, and when configured properly, it stops the majority of automated attacks before they reach your application.

Here's how I configure WAF for production workloads.

## Core Components

An AWS WAF WebACL has three types of rules:

1. **Managed Rule Groups** — AWS-maintained rules (use these first)
2. **Rate-Based Rules** — block IPs exceeding a request threshold
3. **Custom Rules** — your own business logic

Start with managed rules, add rate limiting, then add custom rules for your specific needs.

## The Terraform Configuration

```hcl
module "waf" {
  source = "github.com/kogunlowo123/terraform-aws-waf"

  name  = "production-waf"
  scope = "CLOUDFRONT"  # or "REGIONAL" for ALB

  # AWS Managed Rule Groups (in order of priority)
  managed_rules = [
    {
      name            = "AWSManagedRulesCommonRuleSet"
      priority        = 10
      override_action = "none"  # Block matching requests
    },
    {
      name            = "AWSManagedRulesKnownBadInputsRuleSet"
      priority        = 20
      override_action = "none"
    },
    {
      name            = "AWSManagedRulesSQLiRuleSet"
      priority        = 30
      override_action = "none"
    },
    {
      name            = "AWSManagedRulesBotControlRuleSet"
      priority        = 40
      override_action = "none"
      managed_rule_group_configs = [{
        aws_managed_rules_bot_control_rule_set = {
          inspection_level = "COMMON"  # Upgrade to "TARGETED" for more coverage
        }
      }]
    }
  ]

  # Rate limiting
  rate_based_rules = [
    {
      name           = "rate-limit-all"
      priority       = 100
      limit          = 2000  # requests per 5-minute window
      aggregate_key  = "IP"
      action         = "BLOCK"
    },
    {
      name           = "rate-limit-login"
      priority       = 110
      limit          = 20  # 20 login attempts per 5 min per IP
      aggregate_key  = "IP"
      action         = "BLOCK"
      scope_down_statement = {
        byte_match_statement = {
          field_to_match      = { uri_path = {} }
          positional_constraint = "STARTS_WITH"
          search_string       = "/auth/login"
          text_transformation = [{ priority = 0, type = "LOWERCASE" }]
        }
      }
    }
  ]

  # Logging to S3
  logging_config = {
    log_destination_configs = [aws_kinesis_firehose_delivery_stream.waf_logs.arn]
  }

  tags = local.tags
}
```

## Bot Control Deep Dive

The Bot Control managed rule group is worth the extra cost ($10/month + data processing):

```hcl
# COMMON level catches:
# - Scrapers and crawlers
# - Credential stuffing bots
# - Inventory hoarding bots

# TARGETED level (higher cost) additionally catches:
# - Sophisticated bots that use browser JavaScript
# - CAPTCHA-bypass bots
# - Distributed bot networks

managed_rule_group_configs = [{
  aws_managed_rules_bot_control_rule_set = {
    inspection_level       = "TARGETED"
    enable_machine_learning = true
  }
}]
```

## Custom Rules for Common Scenarios

### Block requests with no User-Agent

```hcl
custom_rules = [
  {
    name     = "block-no-user-agent"
    priority = 200
    action   = "BLOCK"
    statement = {
      not_statement = {
        statement = {
          size_constraint_statement = {
            field_to_match           = { single_header = { name = "user-agent" } }
            comparison_operator      = "GT"
            size                     = 0
            text_transformation      = [{ priority = 0, type = "NONE" }]
          }
        }
      }
    }
  }
]
```

### Allow specific IP ranges (bypass other rules)

```hcl
{
  name     = "allow-corporate-ips"
  priority = 1  # Must be highest priority
  action   = "ALLOW"
  statement = {
    ip_set_reference_statement = {
      arn = aws_wafv2_ip_set.corporate.arn
    }
  }
}
```

### Block requests with SQL injection patterns in query strings

The managed SQLi rules cover most cases, but for custom application logic:

```hcl
{
  name     = "block-sqli-query-params"
  priority = 50
  action   = "BLOCK"
  statement = {
    sqli_match_statement = {
      field_to_match      = { query_string = {} }
      text_transformation = [
        { priority = 1, type = "URL_DECODE" },
        { priority = 2, type = "HTML_ENTITY_DECODE" }
      ]
    }
  }
}
```

## Monitoring WAF Effectiveness

Always deploy a CloudWatch dashboard with your WAF:

```hcl
resource "aws_cloudwatch_metric_alarm" "waf_blocked_requests" {
  alarm_name          = "waf-high-block-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "WAF blocking unusually high number of requests"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    WebACL = aws_wafv2_web_acl.main.name
    Region = var.region
    Rule   = "ALL"
  }
}
```

## Cost Optimization

WAF pricing:
- WebACL: $5/month
- Rules: $1/rule/month
- Requests: $0.60 per million
- Bot Control: $10/month + $1/million requests (COMMON) or $10/million (TARGETED)

For a site with 10M requests/month with Bot Control COMMON: ~$25/month total. For most production workloads, this is the best security ROI in AWS.

## Module

[terraform-aws-waf](https://github.com/kogunlowo123/terraform-aws-waf) — complete WAF configuration with managed rules, rate limiting, logging, and CloudWatch integration.
