# Cloud Security Baseline: CIS Benchmarks with Terraform

**Pillar:** DevSecOps
**SEO Target:** cloud security baseline cis benchmark terraform aws azure gcp
**Word Count:** ~1500

CIS Benchmarks define security best practices for cloud environments. Running continuously, they catch misconfigurations before attackers do. This guide implements CIS AWS Benchmark Level 1 and 2 controls with Terraform: CloudTrail, Config, GuardDuty, Security Hub, and automated remediation.

## CloudTrail Organization Trail

```hcl
resource "aws_cloudtrail" "organization" {
  name                          = "${var.prefix}-org-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cw.arn

  kms_key_id = aws_kms_key.cloudtrail.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }

    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:aws:lambda"]
    }
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  insight_selector {
    insight_type = "ApiErrorRateInsight"
  }

  tags = var.tags
}
```

## AWS Config with CIS Rules

```hcl
resource "aws_config_configuration_recorder" "main" {
  name     = "default"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

locals {
  cis_rules = {
    "root-account-mfa-enabled"     = "ROOT_ACCOUNT_MFA_ENABLED"
    "iam-root-access-key-check"    = "IAM_ROOT_ACCESS_KEY_CHECK"
    "cloudtrail-enabled"           = "CLOUD_TRAIL_ENABLED"
    "s3-bucket-public-read"        = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    "s3-bucket-public-write"       = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
    "vpc-default-sg-closed"        = "VPC_DEFAULT_SECURITY_GROUP_CLOSED"
    "ebs-volume-encrypted"         = "ENCRYPTED_VOLUMES"
    "rds-storage-encrypted"        = "RDS_STORAGE_ENCRYPTED"
    "guardduty-enabled"            = "GUARDDUTY_ENABLED_CENTRALIZED"
    "securityhub-enabled"          = "SECURITYHUB_ENABLED"
    "access-keys-rotated-90"       = "ACCESS_KEYS_ROTATED"
    "password-policy-min-length"   = "IAM_PASSWORD_POLICY"
  }
}

resource "aws_config_config_rule" "cis" {
  for_each = local.cis_rules
  name     = each.key

  source {
    owner             = "AWS"
    source_identifier = each.value
  }

  depends_on = [aws_config_configuration_recorder.main]
}
```

## Security Hub

```hcl
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/3.0.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}
```

## Automated Remediation

```hcl
resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  name        = "${var.prefix}-security-hub-critical"
  description = "Trigger remediation on CRITICAL Security Hub findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = { Label = ["CRITICAL", "HIGH"] }
        Workflow  = { Status = ["NEW"] }
        RecordState = ["ACTIVE"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "remediation_lambda" {
  rule = aws_cloudwatch_event_rule.security_hub_findings.name
  arn  = aws_lambda_function.auto_remediation.arn
}
```

## Production Checklist

- [ ] Multi-region CloudTrail with log file validation + Insights
- [ ] CloudTrail logs to S3 with KMS encryption and Object Lock
- [ ] AWS Config recording all resources including global (IAM)
- [ ] CIS Benchmark 3.0 rules via Security Hub (replaces manual Config rules)
- [ ] GuardDuty enabled in all regions (required for CIS Level 2)
- [ ] Security Hub aggregating findings from all accounts in org
- [ ] EventBridge rule triggers Lambda remediation on CRITICAL findings
- [ ] CloudWatch alarm on Config non-compliance count > 0
- [ ] Root account MFA enforced and access keys absent (CIS 1.1, 1.4)

CIS Benchmark compliance isn't a one-time audit — it's a continuous signal. Security Hub gives you a compliance score updated in near-real-time as resources change, making drift visible before it becomes a breach.

## About This Guide

This guide is part of the Citadel Cloud Management content series covering AWS, Azure, GCP, DevSecOps, MCP Servers, and Cloud Careers. Follow our GitHub: https://github.com/kogunlowo123/citadel-cloud-management
