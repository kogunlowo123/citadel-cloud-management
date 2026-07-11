---
title: "AWS Security Baseline with Terraform: GuardDuty, Security Hub & Config in 30 Minutes"
published: true
description: "Deploy a complete AWS security baseline with Terraform: GuardDuty, Security Hub, AWS Config, CloudTrail, and Access Analyzer. All five services, one module, under 30 minutes."
tags: aws, terraform, security, devops
series: "Citadel Cloud Management: 100 Free Terraform Guides"
canonical_url: https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/08-aws-security-baseline-devsecops.md
cover_image: https://kogunlowo123.github.io/citadel-cloud-management/assets/images/og-default.png
---

> **This is part of the [Citadel Cloud Management](https://github.com/kogunlowo123/citadel-cloud-management) free Terraform guide library — 100+ production-ready guides, MIT licensed, no paywall.**

The average AWS account takes 277 days to identify and contain a breach. Most of that time is lost because security tooling wasn't configured before the breach — it was configured after.

Here's the security baseline I deploy on every new AWS account, in under 30 minutes.

## The Five Services You Need

| Service | What It Does |
|---------|-------------|
| **GuardDuty** | ML threat detection (CloudTrail, VPC Flow Logs, DNS) |
| **Security Hub** | Aggregates findings from all security services |
| **AWS Config** | Tracks config changes + compliance checks |
| **CloudTrail** | Full API audit trail, multi-region |
| **Access Analyzer** | Finds overly permissive IAM policies |

## The Module

```hcl
module "security_baseline" {
  source = "github.com/kogunlowo123/terraform-aws-security-baseline"

  enable_guardduty       = true
  enable_security_hub    = true
  enable_config          = true
  enable_cloudtrail      = true
  enable_access_analyzer = true

  cloudtrail_s3_bucket = aws_s3_bucket.security_logs.id
  config_s3_bucket     = aws_s3_bucket.config_logs.id
  alarm_sns_topic_arn  = aws_sns_topic.security_alerts.arn

  security_hub_standards = [
    "aws-foundational-security-best-practices/v/1.0.0",
    "cis-aws-foundations-benchmark/v/1.4.0"
  ]

  tags = local.tags
}
```

## GuardDuty Configuration

```hcl
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs { enable = true }
    kubernetes {
      audit_logs { enable = true }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes { enable = true }
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "${var.prefix}-guardduty-high-severity"
  description = "Route HIGH severity GuardDuty findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
}
```

## AWS Config with CIS Compliance

```hcl
resource "aws_config_configuration_recorder" "main" {
  name     = "${var.prefix}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_conformance_pack" "cis" {
  name = "${var.prefix}-cis-benchmark"

  template_body = <<-EOT
    Parameters:
      AccessKeysRotatedParamMaxAccessKeyAge:
        Type: String
        Default: "90"
    Resources:
      AccessKeysRotated:
        Type: AWS::Config::ConfigRule
        Properties:
          Source:
            Owner: AWS
            SourceIdentifier: ACCESS_KEYS_ROTATED
          InputParameters:
            maxAccessKeyAge: !Ref AccessKeysRotatedParamMaxAccessKeyAge
      RootMFAEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          Source:
            Owner: AWS
            SourceIdentifier: ROOT_ACCOUNT_MFA_ENABLED
  EOT
}
```

## CloudTrail with Log File Validation

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "${var.prefix}-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.security_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]  # All S3 data events
    }
  }
}
```

## Security Hub Auto-Remediation

```hcl
# Auto-suppress informational findings
resource "aws_securityhub_automation_rule" "suppress_informational" {
  rule_name        = "suppress-informational"
  rule_order       = 1
  description      = "Suppress INFORMATIONAL findings"
  is_terminal      = false

  criteria {
    severity_label {
      value      = "INFORMATIONAL"
      comparison = "EQUALS"
    }
  }

  actions {
    type              = "FINDING_FIELDS_UPDATE"
    finding_fields_to_update {
      workflow { status = "SUPPRESSED" }
      note {
        text       = "Auto-suppressed: informational severity"
        updated_by = "automation-rule"
      }
    }
  }
}
```

## Production Checklist

- [ ] GuardDuty enabled with S3, Kubernetes, and malware protection datasources
- [ ] Security Hub aggregating from GuardDuty, Config, Inspector, Macie
- [ ] CloudTrail: multi-region, log file validation, KMS encryption
- [ ] Config recorder + delivery channel + S3 logging
- [ ] CIS Benchmark conformance pack
- [ ] SNS topic for HIGH/CRITICAL findings → PagerDuty/OpsGenie
- [ ] Access Analyzer for each region + organization analyzer
- [ ] GuardDuty findings auto-archived after 90 days

## Full Code

Complete guide with all IAM roles, S3 bucket policies, KMS key configuration, and Security Hub integrations:

👉 [github.com/kogunlowo123/citadel-cloud-management — Article 08](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/08-aws-security-baseline-devsecops.md)

---

*Part of 100 free production Terraform guides covering AWS, Azure, GCP, Kubernetes, DevSecOps, AI/ML, and Cloud Careers. MIT licensed. [Browse the full library →](https://github.com/kogunlowo123/citadel-cloud-management)*
