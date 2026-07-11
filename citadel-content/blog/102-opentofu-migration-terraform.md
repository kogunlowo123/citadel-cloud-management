# Migrating from Terraform to OpenTofu: Complete Production Guide

**Pillar:** Multi-Cloud Architecture
**SEO Target:** opentofu migration terraform, opentofu vs terraform production, migrate terraform opentofu
**Word Count:** ~1,900

OpenTofu is the open-source fork of Terraform maintained by the Linux Foundation after HashiCorp's BSL license change in August 2023. For most workloads, OpenTofu is a drop-in replacement — same HCL syntax, same provider ecosystem, same state format. This guide covers the complete migration path for production infrastructure, including state migration, CI/CD updates, and the features OpenTofu adds that Terraform doesn't have.

## OpenTofu vs Terraform: What Actually Changed

| Aspect | Terraform (BSL) | OpenTofu (MPL-2.0) |
|--------|----------------|-------------------|
| License | Business Source License | Mozilla Public License 2.0 |
| Commercial use | Restricted (competing products) | Unrestricted |
| State encryption | Not available | Built-in AES-GCM |
| Provider mocking | Not available | Built-in for testing |
| Registry | registry.terraform.io | registry.opentofu.org |
| CLI compatibility | n/a | `tofu` replaces `terraform` |
| Provider support | Full | Full (same providers) |
| Modules | Full | Full |

For most cloud engineers: the migration is a binary swap + registry URL change. For security-conscious teams: state encryption alone is worth migrating.

## Installation via Terraform

```hcl
# Install OpenTofu alongside Terraform for parallel comparison
resource "null_resource" "opentofu_install" {
  provisioner "local-exec" {
    command = <<-EOT
      # Linux/macOS
      curl -fsSL https://get.opentofu.org/install-opentofu.sh | bash -s -- --install-method standalone
      tofu --version
    EOT
  }
}
```

Or via Homebrew / package manager:
```bash
brew install opentofu         # macOS
apt install opentofu           # Debian/Ubuntu
winget install opentofu.opentofu  # Windows
```

## Step 1: Verify Compatibility

```bash
# Check your .terraform.lock.hcl for provider versions
cat .terraform.lock.hcl | grep -E "registry|version"

# OpenTofu uses registry.opentofu.org (mirrors terraform registry)
# No changes needed — providers are the same
```

## Step 2: Update Provider Sources (Optional but Recommended)

```hcl
# Before (Terraform)
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# After (OpenTofu) — works with either registry
terraform {
  required_version = ">= 1.8"  # OpenTofu uses same version scheme
  required_providers {
    aws = {
      source  = "hashicorp/aws"  # or "registry.opentofu.org/hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

## Step 3: State Migration (Zero Downtime)

```bash
# 1. Take state backup first
terraform state pull > terraform.tfstate.backup
aws s3 cp terraform.tfstate.backup s3://my-tf-state-bucket/backups/$(date +%Y%m%d)/

# 2. Initialize OpenTofu with existing state
tofu init \
  -backend-config="bucket=my-tf-state-bucket" \
  -backend-config="key=prod/terraform.tfstate" \
  -backend-config="region=us-east-1"

# 3. Verify state is readable
tofu state list | wc -l

# 4. Run plan to confirm zero diff
tofu plan -out=migration.plan

# 5. If plan shows no changes, migration is complete
tofu show migration.plan | grep "No changes"
```

## Step 4: State Encryption (OpenTofu-Exclusive Feature)

```hcl
# opentofu-only: encrypt state at rest with AES-GCM
terraform {
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_encryption_passphrase
    }

    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method = method.aes_gcm.main
    }

    plan {
      method = method.aes_gcm.main
    }
  }

  backend "s3" {
    bucket         = var.state_bucket
    key            = "${var.environment}/terraform.tfstate"
    region         = var.region
    encrypt        = true
    dynamodb_table = var.state_lock_table
  }
}
```

For AWS KMS-backed encryption:

```hcl
terraform {
  encryption {
    key_provider "aws_kms" "main" {
      kms_key_id = aws_kms_key.state.arn
      region     = var.region
    }

    method "aes_gcm" "main" {
      keys = key_provider.aws_kms.main
    }

    state {
      method = method.aes_gcm.main

      # Rollback config — use this if you need to read state with Terraform
      fallback {
        method = method.unencrypted
      }
    }
  }
}
```

## Step 5: Update CI/CD Pipeline

### GitHub Actions

```yaml
# .github/workflows/tofu-plan.yml
name: OpenTofu Plan

on:
  pull_request:
    paths:
      - '**/*.tf'
      - '**/*.tfvars'

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: "1.8.0"

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.PLAN_ROLE_ARN }}
          aws-region: us-east-1

      - name: OpenTofu Init
        run: tofu init

      - name: OpenTofu Plan
        id: plan
        run: |
          tofu plan -no-color -out=plan.tfplan 2>&1 | tee plan.txt
          echo "exitcode=$?" >> $GITHUB_OUTPUT

      - name: Comment PR with plan
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs')
            const plan = fs.readFileSync('plan.txt', 'utf8')
            const truncated = plan.length > 60000 ? plan.slice(-60000) : plan
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `## OpenTofu Plan\n\`\`\`\n${truncated}\n\`\`\``
            })

  apply:
    runs-on: ubuntu-latest
    needs: plan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: "1.8.0"

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.APPLY_ROLE_ARN }}
          aws-region: us-east-1

      - name: OpenTofu Apply
        run: |
          tofu init
          tofu apply -auto-approve
```

## Step 6: Provider Mocking for Tests (OpenTofu-Exclusive)

```hcl
# test/mock_providers.tfmock
mock_provider "aws" {
  mock_resource "aws_instance" {
    defaults = {
      id         = "i-0123456789abcdef0"
      arn        = "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0"
      public_ip  = "203.0.113.10"
      private_ip = "10.0.1.100"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      id                   = "mock-bucket-id"
      bucket               = "mock-bucket"
      bucket_domain_name   = "mock-bucket.s3.amazonaws.com"
    }
  }
}

# test/main.tftest.hcl
run "creates_vpc" {
  command = plan

  providers = {
    aws = mock_provider.aws
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR must be 10.0.0.0/16"
  }

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Must create 3 private subnets"
  }
}
```

Run tests without AWS credentials:

```bash
tofu test -filter=test/main.tftest.hcl
```

## Drift Detection Workflow

```hcl
# .github/workflows/drift-detection.yml
# Detects infrastructure drift daily
```

See article 104 for the complete drift detection workflow.

## Rollback Strategy

```bash
# If you need to roll back to Terraform:
# 1. State format is identical — just switch CLI
terraform state pull  # reads the same state
terraform plan        # verify no diff

# If you used state encryption:
# 1. Decrypt state first with OpenTofu
tofu state pull > decrypted-state.json
# 2. Remove encryption config
# 3. Push state back unencrypted
terraform state push decrypted-state.json
```

## Variables

```hcl
variable "state_bucket" {
  description = "S3 bucket for Terraform/OpenTofu state"
  type        = string
}

variable "state_lock_table" {
  description = "DynamoDB table for state locking"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "state_encryption_passphrase" {
  description = "Passphrase for state encryption (store in AWS Secrets Manager)"
  type        = string
  sensitive   = true
}
```

## Production Checklist

- [ ] State backup taken before migration
- [ ] `tofu init` succeeds with existing S3 backend
- [ ] `tofu plan` shows zero changes after migration
- [ ] CI/CD uses `opentofu/setup-opentofu@v1` action
- [ ] State encryption enabled with KMS key (OpenTofu-exclusive feature)
- [ ] KMS key rotation enabled on state encryption key
- [ ] Provider mocking configured for unit tests (no AWS credentials needed)
- [ ] Drift detection workflow scheduled daily
- [ ] Team trained on `tofu` CLI (identical commands to `terraform`)
- [ ] `.terraform.lock.hcl` committed and not gitignored

The OpenTofu migration for most teams is a 2-hour task: install `tofu`, run `tofu init` against existing state, update CI/CD, and enjoy the BSL-free license plus state encryption and provider mocking that Terraform doesn't offer.
