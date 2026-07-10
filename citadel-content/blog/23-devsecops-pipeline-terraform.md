# DevSecOps Pipeline with Terraform: Security Scanning in CI/CD

**Pillar:** DevSecOps
**SEO Target:** devsecops pipeline terraform security scanning cicd
**Word Count:** ~1700

DevSecOps integrates security scanning into every stage of the CI/CD pipeline — shifting security left so vulnerabilities are caught before production. This guide builds a complete DevSecOps pipeline using GitHub Actions, Terraform infrastructure, and a suite of open-source security tools.

## Security Scanning Layers

A complete DevSecOps pipeline scans at multiple levels:

| Layer | Tool | What It Catches |
|-------|------|-----------------|
| SAST | Semgrep, Bandit | Code vulnerabilities |
| SCA | Trivy, Grype | Dependency CVEs |
| IaC | Checkov, tfsec | Terraform misconfigs |
| Container | Trivy | Base image CVEs |
| Secrets | Gitleaks, TruffleHog | Leaked credentials |
| DAST | OWASP ZAP | Runtime vulnerabilities |

## Terraform Infrastructure

```hcl
# S3 bucket for security scan results
resource "aws_s3_bucket" "security_reports" {
  bucket = "${var.prefix}-security-reports-${var.account_id}"
}

resource "aws_s3_bucket_versioning" "security_reports" {
  bucket = aws_s3_bucket.security_reports.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "security_reports" {
  bucket                  = aws_s3_bucket.security_reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "security_reports" {
  bucket = aws_s3_bucket.security_reports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
  }
}

# ECR for scanning container images
resource "aws_ecr_repository" "app" {
  name                 = "${var.prefix}/${var.app_name}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }
}

# SecurityHub for centralized findings
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
}

resource "aws_securityhub_standards_subscription" "aws_best_practices" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}
```

## GitHub Actions Pipeline

```yaml
name: DevSecOps Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  secrets-scan:
    name: Secrets Detection
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Gitleaks scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  sast:
    name: Static Analysis
    runs-on: ubuntu-latest
    needs: secrets-scan
    steps:
      - uses: actions/checkout@v4

      - name: Semgrep scan
        uses: semgrep/semgrep-action@v1
        with:
          config: >-
            p/security-audit
            p/owasp-top-ten
            p/secrets
        env:
          SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }}

  iac-scan:
    name: Infrastructure Security
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Checkov IaC scan
        uses: bridgecrewio/checkov-action@master
        with:
          directory: .
          framework: terraform
          output_format: sarif
          output_file_path: checkov-results.sarif
          soft_fail: false
          skip_check: CKV_AWS_144,CKV2_AWS_6

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: checkov-results.sarif

      - name: tfsec scan
        uses: aquasecurity/tfsec-action@v1.0.0
        with:
          soft_fail: false

  sca:
    name: Dependency Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Trivy filesystem scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          scan-ref: .
          format: sarif
          output: trivy-fs-results.sarif
          severity: CRITICAL,HIGH
          exit-code: 1

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: trivy-fs-results.sarif

  container-scan:
    name: Container Security
    runs-on: ubuntu-latest
    needs: [sast, sca, iac-scan]
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build image
        run: |
          docker build -t ${{ steps.login-ecr.outputs.registry }}/myapp:${{ github.sha }} .

      - name: Trivy image scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ steps.login-ecr.outputs.registry }}/myapp:${{ github.sha }}
          format: sarif
          output: trivy-image-results.sarif
          severity: CRITICAL,HIGH
          exit-code: 1

      - name: Push to ECR (only on main)
        if: github.ref == 'refs/heads/main'
        run: |
          docker push ${{ steps.login-ecr.outputs.registry }}/myapp:${{ github.sha }}

  deploy:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: container-scan
    if: github.ref == 'refs/heads/main'
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Plan
        run: |
          terraform init
          terraform plan -var="image_tag=${{ github.sha }}" -out=tfplan

      - name: Terraform Apply
        run: terraform apply tfplan
```

## Security Gates Policy

```hcl
# IAM policy for CI/CD — read-only for plan, write for apply
resource "aws_iam_role" "cicd" {
  name = "${var.prefix}-cicd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cicd_ecr" {
  name = "ecr-push"
  role = aws_iam_role.cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = aws_ecr_repository.app.arn
      }
    ]
  })
}
```

## Security Finding Notifications

```hcl
resource "aws_cloudwatch_event_rule" "security_findings" {
  name        = "${var.prefix}-security-findings"
  description = "Capture Security Hub high/critical findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = { Label = ["HIGH", "CRITICAL"] }
        RecordState = ["ACTIVE"]
        WorkflowState = ["NEW"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "security_findings_sns" {
  rule      = aws_cloudwatch_event_rule.security_findings.name
  target_id = "SecurityFindingsSNS"
  arn       = aws_sns_topic.security_alerts.arn
}
```

## Production Checklist

- [ ] Gitleaks in pre-commit hooks (not just CI)
- [ ] SARIF output uploaded to GitHub Security tab
- [ ] Exit code 1 on CRITICAL/HIGH — pipeline blocks on findings
- [ ] Container images scanned before push to ECR
- [ ] ECR image scanning enabled (scan on push)
- [ ] SecurityHub enabled with CIS and AWS Best Practices standards
- [ ] GitHub OIDC for AWS auth — no long-lived credentials in secrets
- [ ] Security findings → SNS → PagerDuty/Slack alerts
- [ ] Terraform plan in PR, apply only on main merge
- [ ] Checkov skip list documented with justification

Shifting security left with this pipeline means a leaked secret or a critical CVE in a dependency blocks the deployment before it ever reaches production — not after.
