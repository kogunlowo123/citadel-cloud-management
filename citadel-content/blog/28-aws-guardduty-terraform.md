# AWS GuardDuty with Terraform: Automated Threat Detection

**Pillar:** DevSecOps
**SEO Target:** aws guardduty terraform threat detection security
**Word Count:** ~1500

GuardDuty is AWS's managed threat detection service — it ingests CloudTrail API calls, VPC Flow Logs, and DNS logs, then applies ML and threat intelligence to detect account compromises, data exfiltration, and crypto-mining. This guide enables GuardDuty across all regions with centralized findings via Terraform.

## What GuardDuty Detects

- **IAM findings**: Unusual API calls, credential theft, privilege escalation
- **EC2 findings**: Malware, port scanning, crypto mining, communication with known bad IPs
- **S3 findings**: Data exfiltration, bucket policy modifications, anonymous access
- **EKS findings**: Privileged container launches, exposed API servers
- **Lambda findings**: Malicious code execution patterns
- **RDS findings**: Credential brute force, suspicious SQL queries

## Enable GuardDuty

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

  tags = var.tags
}
```

## Multi-Region Setup

```hcl
locals {
  enabled_regions = [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "eu-west-1", "eu-central-1", "ap-southeast-1"
  ]
}

module "guardduty" {
  source   = "./modules/guardduty"
  for_each = toset(local.enabled_regions)

  providers = {
    aws = aws.regions[each.key]
  }

  tags = var.tags
}
```

## EventBridge Rule for Findings

```hcl
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-findings"
  description = "Capture all GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "findings_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "GuardDutyFindingsSNS"
  arn       = aws_sns_topic.security_alerts.arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      type        = "$.detail.type"
      description = "$.detail.description"
      region      = "$.region"
      account     = "$.account"
    }
    input_template = <<EOF
{
  "severity": "<severity>",
  "type": "<type>",
  "description": "<description>",
  "region": "<region>",
  "account": "<account>"
}
EOF
  }
}
```

## High-Severity Alert Lambda

```hcl
resource "aws_cloudwatch_event_rule" "high_severity" {
  name = "guardduty-high-severity"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "high_severity_lambda" {
  rule      = aws_cloudwatch_event_rule.high_severity.name
  target_id = "AutoRemediation"
  arn       = aws_lambda_function.guardduty_remediation.arn
}

resource "aws_lambda_permission" "guardduty_trigger" {
  statement_id  = "AllowGuardDutyTrigger"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guardduty_remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.high_severity.arn
}
```

## Auto-Remediation Lambda

```python
# lambda/guardduty_remediation.py
import boto3
import json

ec2 = boto3.client('ec2')
iam = boto3.client('iam')

REMEDIATION_ACTIONS = {
    "UnauthorizedAccess:IAMUser/MaliciousIPCaller": remediate_iam_compromise,
    "Recon:EC2/PortProbeUnprotectedPort": isolate_ec2_instance,
    "CryptoCurrency:EC2/BitcoinTool.B!DNS": isolate_ec2_instance,
}

def handler(event, context):
    finding = event['detail']
    finding_type = finding['type']
    severity = finding['severity']
    
    print(f"Processing finding: {finding_type} (severity: {severity})")
    
    remediation_fn = REMEDIATION_ACTIONS.get(finding_type)
    if remediation_fn:
        remediation_fn(finding)
    else:
        print(f"No automated remediation for {finding_type}")
    
    return {"statusCode": 200}

def isolate_ec2_instance(finding):
    instance_id = finding['resource']['instanceDetails']['instanceId']
    
    # Move instance to quarantine security group
    ec2.modify_instance_attribute(
        InstanceId=instance_id,
        Groups=[QUARANTINE_SG_ID]
    )
    
    print(f"Isolated EC2 instance: {instance_id}")

def remediate_iam_compromise(finding):
    user_name = finding['resource']['accessKeyDetails'].get('userName')
    if user_name:
        # Disable all access keys for the compromised user
        keys = iam.list_access_keys(UserName=user_name)['AccessKeyMetadata']
        for key in keys:
            iam.update_access_key(
                UserName=user_name,
                AccessKeyId=key['AccessKeyId'],
                Status='Inactive'
            )
        print(f"Disabled access keys for user: {user_name}")
```

## GuardDuty Suppression Rules

```hcl
resource "aws_guardduty_filter" "suppress_trusted_ips" {
  name        = "suppress-trusted-scanner"
  action      = "ARCHIVE"
  detector_id = aws_guardduty_detector.main.id
  rank        = 1

  finding_criteria {
    criterion {
      field  = "type"
      equals = ["Recon:EC2/PortProbeUnprotectedPort"]
    }
    criterion {
      field  = "service.remoteIpDetails.ipAddressV4"
      equals = var.trusted_scanner_ips
    }
  }
}
```

## Finding Export to S3

```hcl
resource "aws_guardduty_publishing_destination" "s3" {
  detector_id     = aws_guardduty_detector.main.id
  destination_arn = aws_s3_bucket.guardduty_findings.arn
  kms_key_arn     = aws_kms_key.guardduty.arn
}

resource "aws_s3_bucket" "guardduty_findings" {
  bucket = "${var.prefix}-guardduty-findings-${var.account_id}"
}

resource "aws_s3_bucket_policy" "guardduty_findings" {
  bucket = aws_s3_bucket.guardduty_findings.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GuardDutyWrite"
        Effect = "Allow"
        Principal = { Service = "guardduty.amazonaws.com" }
        Action   = ["s3:GetBucketLocation", "s3:PutObject"]
        Resource = [
          aws_s3_bucket.guardduty_findings.arn,
          "${aws_s3_bucket.guardduty_findings.arn}/*"
        ]
      }
    ]
  })
}
```

## CloudWatch Alarm for Finding Volume

```hcl
resource "aws_cloudwatch_metric_alarm" "guardduty_finding_volume" {
  alarm_name          = "${var.prefix}-guardduty-high-finding-volume"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FindingsCount"
  namespace           = "AWS/GuardDuty"
  period              = 3600
  statistic           = "Sum"
  threshold           = 10

  dimensions = {
    DetectorId = aws_guardduty_detector.main.id
    FindingType = "HIGH"
  }

  alarm_actions = [aws_sns_topic.security_alerts.arn]
}
```

## Outputs

```hcl
output "detector_id" {
  value = aws_guardduty_detector.main.id
}

output "findings_bucket" {
  value = aws_s3_bucket.guardduty_findings.bucket
}
```

## Production Checklist

- [ ] GuardDuty enabled in all regions (not just primary)
- [ ] S3 Protection enabled
- [ ] EKS Audit Log Monitoring enabled
- [ ] Malware Protection with EBS scanning
- [ ] EventBridge rule forwards all findings to SNS
- [ ] Auto-remediation Lambda for HIGH/CRITICAL findings
- [ ] Suppression rules for known-good scanner IPs
- [ ] Findings exported to S3 with KMS encryption
- [ ] CloudWatch alarm triggers on high finding volume
- [ ] Findings integrated into Security Hub

GuardDuty with EventBridge-driven auto-remediation turns passive threat detection into an active security posture — compromised credentials get disabled automatically before the attacker can act.
