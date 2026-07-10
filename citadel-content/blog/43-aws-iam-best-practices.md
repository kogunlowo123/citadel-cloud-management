# AWS IAM Best Practices: Least Privilege with Terraform

**Pillar:** AWS Infrastructure
**SEO Target:** aws iam least privilege terraform permission boundaries scp
**Word Count:** ~1500

IAM is the most critical security control in AWS. Overly permissive policies are the root cause of most cloud security incidents. This guide implements least-privilege IAM with Terraform: permission boundaries, Service Control Policies, IAM Access Analyzer, and automated policy validation.

## Permission Boundaries

```hcl
resource "aws_iam_policy" "developer_boundary" {
  name        = "${var.prefix}-developer-boundary"
  description = "Maximum permissions any developer-created role can have"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowedServices"
        Effect = "Allow"
        Action = [
          "s3:*", "sqs:*", "sns:*",
          "lambda:*", "dynamodb:*",
          "cloudwatch:*", "logs:*",
          "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyIAMEscalation"
        Effect = "Deny"
        Action = [
          "iam:CreateRole", "iam:AttachRolePolicy",
          "iam:PutRolePolicy", "iam:CreatePolicy",
          "iam:CreateUser", "iam:AttachUserPolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyNetworkChanges"
        Effect = "Deny"
        Action = ["ec2:CreateVpc", "ec2:ModifyVpcAttribute"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "app_role" {
  name                 = "${var.prefix}-app"
  permissions_boundary = aws_iam_policy.developer_boundary.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
```

## Service Control Policy (AWS Organizations)

```hcl
resource "aws_organizations_policy" "security_guardrails" {
  name        = "SecurityGuardrails"
  description = "Prevent disabling of security services"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDisableGuardDuty"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:StopMonitoringMembers"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyDisableCloudTrail"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyLeaveOrg"
        Effect = "Deny"
        Action = ["organizations:LeaveOrganization"]
        Resource = "*"
      },
      {
        Sid    = "RequireMFA"
        Effect = "Deny"
        Action = ["*"]
        Resource = "*"
        Condition = {
          BoolIfExists = {
            "aws:MultiFactorAuthPresent" = "false"
          }
          StringNotLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:role/Automation-*"
          }
        }
      }
    ]
  })
}
```

## IAM Access Analyzer

```hcl
resource "aws_accessanalyzer_analyzer" "organization" {
  analyzer_name = "${var.prefix}-org-analyzer"
  type          = "ORGANIZATION"
  tags          = var.tags
}

resource "aws_accessanalyzer_archive_rule" "known_external" {
  analyzer_name = aws_accessanalyzer_analyzer.organization.analyzer_name
  rule_name     = "known-external-accounts"

  filter {
    criteria = "principal.AWS"
    contains = var.trusted_account_ids
  }
}
```

## Automated Policy Validation

```hcl
resource "aws_config_config_rule" "iam_no_inline" {
  name = "iam-no-inline-policy"

  source {
    owner             = "AWS"
    source_identifier = "IAM_NO_INLINE_POLICY_CHECK"
  }

  scope {
    compliance_resource_types = ["AWS::IAM::User", "AWS::IAM::Role", "AWS::IAM::Group"]
  }
}

resource "aws_config_config_rule" "iam_policy_no_statements_with_admin" {
  name = "iam-policy-no-full-admin"

  source {
    owner             = "AWS"
    source_identifier = "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS"
  }
}
```

## Production Checklist

- [ ] Permission boundaries on all developer-created roles
- [ ] SCPs block: disabling GuardDuty/CloudTrail, leaving organization
- [ ] MFA required for all human users via SCP condition
- [ ] IAM Access Analyzer at organization level (finds external access)
- [ ] AWS Config rules: no inline policies, no admin access
- [ ] No wildcard (*) on Resource in production policies
- [ ] Separate roles per service (not one shared role with all permissions)
- [ ] Cross-account access via assume-role with ExternalId
- [ ] Regular Access Advisor review (remove permissions unused 90+ days)

Permission boundaries are the most underused IAM feature. They let you delegate role creation to developers while ensuring they can never create a role more powerful than the boundary — a key control for a developer self-service model.

## About This Guide

This guide is part of the Citadel Cloud Management content series covering AWS, Azure, GCP, DevSecOps, MCP Servers, and Cloud Careers. Follow our GitHub: https://github.com/kogunlowo123/citadel-cloud-management
