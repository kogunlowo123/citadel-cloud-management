# AWS Security Baseline with Terraform: GuardDuty, Security Hub, and Config in 30 Minutes

**Pillar:** DevSecOps
**SEO Target:** "aws security baseline terraform", "terraform guardduty security hub config"
**Word Count:** ~2,100

---

The average AWS account takes 277 days to identify and contain a breach. Most of that time is lost because security tooling wasn't configured before the breach — it was configured after.

Here's the security baseline I deploy on every new AWS account, all with Terraform, completable in under 30 minutes.

## Why These Five Services

Every AWS security baseline should include:

1. **GuardDuty** — ML-powered threat detection across CloudTrail, VPC Flow Logs, and DNS
2. **Security Hub** — aggregates findings from all security services into one view
3. **AWS Config** — tracks configuration changes and checks compliance
4. **CloudTrail** — full API audit trail, multi-region
5. **Access Analyzer** — finds overly permissive policies

These five together give you: threat detection, compliance, audit trail, and policy analysis. Everything else (WAF, Macie, Detective) layers on top.

## The Module

```hcl
module "security_baseline" {
  source = "github.com/kogunlowo123/terraform-aws-security-baseline"

  enable_guardduty       = true
  enable_security_hub    = true
  enable_config          = true
  enable_cloudtrail      = true
  enable_access_analyzer = true

  # Centralize logs
  cloudtrail_s3_bucket   = aws_s3_bucket.security_logs.id
  config_s3_bucket       = aws_s3_bucket.config_logs.id

  # Alerting
  alarm_sns_topic_arn    = aws_sns_topic.security_alerts.arn

  # Security Hub standards
  security_hub_standards = [
    "aws-foundational-security-best-practices/v/1.0.0",
    "cis-aws-foundations-benchmark/v/1.4.0",
    "pci-dss/v/3.2.1"
  ]

  tags = local.tags
}
```

## GuardDuty Deep Dive

GuardDuty uses machine learning to detect:

- **Reconnaissance** — port scanning, unusual API calls
- **Instance compromise** — crypto mining, C2 communication, backdoors
- **Account compromise** — unusual IAM activity, root account usage
- **S3 threats** — unusual data access patterns, policy changes

```hcl
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  finding_publishing_frequency = "FIFTEEN_MINUTES"
}
```

Enable malware protection — it scans EBS volumes of instances flagged by GuardDuty.

## Security Hub with Automated Remediation

Security Hub is most powerful when combined with EventBridge and Lambda for auto-remediation:

```hcl
# EventBridge rule to capture HIGH/CRITICAL findings
resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  name        = "security-hub-high-critical"
  description = "Capture HIGH and CRITICAL Security Hub findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["HIGH", "CRITICAL"]
        }
        Workflow = {
          Status = ["NEW"]
        }
      }
    }
  })
}

# Route to SNS for immediate alerting
resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.security_hub_findings.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}
```

## AWS Config Rules

Config rules are compliance-as-code — they check your infrastructure against a policy and flag violations:

```hcl
locals {
  config_rules = {
    "s3-bucket-public-read-prohibited"    = {}
    "s3-bucket-public-write-prohibited"   = {}
    "s3-bucket-ssl-requests-only"         = {}
    "encrypted-volumes"                    = {}
    "rds-instance-public-access-check"    = {}
    "rds-storage-encrypted"               = {}
    "ec2-imdsv2-check"                    = {}
    "root-account-mfa-enabled"            = {}
    "iam-password-policy"                 = {
      RequireUppercaseCharacters = "true"
      RequireSymbols             = "true"
      MinimumPasswordLength      = "14"
    }
    "vpc-flow-logs-enabled"              = {}
  }
}

resource "aws_config_config_rule" "rules" {
  for_each = local.config_rules
  name     = each.key

  source {
    owner             = "AWS"
    source_identifier = upper(replace(each.key, "-", "_"))
  }

  input_parameters = length(each.value) > 0 ? jsonencode(each.value) : null
}
```

## CloudTrail Best Practices

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "org-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Log S3 data events for sensitive buckets
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::sensitive-bucket/"]
    }
  }

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn
}
```

Always enable log file validation — it detects tampering with the audit trail.

## Cost of This Baseline

For a typical account:
- GuardDuty: ~$15-30/month
- Security Hub: ~$5-10/month
- Config: ~$10-20/month (depends on resource count and rule evaluations)
- CloudTrail: Free for management events; S3 storage ~$2-5/month

Total: ~$30-65/month for comprehensive security coverage. The cost of a breach is orders of magnitude higher.

## Module

[terraform-aws-security-baseline](https://github.com/kogunlowo123/terraform-aws-security-baseline) — deploys all five services with sensible defaults.
