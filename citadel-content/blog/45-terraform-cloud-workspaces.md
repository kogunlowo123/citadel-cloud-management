# Terraform Cloud: Remote State, Workspaces, and CI/CD

**Pillar:** Multi-Cloud Architecture
**SEO Target:** terraform cloud remote state workspaces ci/cd sentinel policies
**Word Count:** ~1500

Terraform Cloud centralizes state management, adds collaboration features, and provides Sentinel policy enforcement. For teams beyond two people, local state files in S3 create friction; Terraform Cloud eliminates it. This guide migrates from S3 backend to Terraform Cloud, configures workspaces, and implements Sentinel cost controls.

## Migrating from S3 Backend

```hcl
# Before: S3 backend
terraform {
  backend "s3" {
    bucket = "citadel-tfstate"
    key    = "production/terraform.tfstate"
    region = "us-east-1"
  }
}

# After: Terraform Cloud
terraform {
  cloud {
    organization = var.tfc_organization

    workspaces {
      tags = ["production", "aws"]
    }
  }
}
```

## Workspace Structure

```hcl
resource "tfe_workspace" "main" {
  name         = "${var.prefix}-production"
  organization = var.tfc_organization
  project_id   = tfe_project.infrastructure.id

  execution_mode       = "remote"
  terraform_version    = "~> 1.9"
  auto_apply           = false
  queue_all_runs       = true
  assessments_enabled  = true

  vcs_repo {
    identifier         = "kogunlowo123/citadel-cloud-management"
    branch             = "main"
    oauth_token_id     = var.tfc_oauth_token_id
    ingress_submodules = false
    tags_regex         = null
  }

  working_directory = "environments/production"

  trigger_patterns = ["modules/**/*", "environments/production/**/*"]
}
```

## Variable Sets

```hcl
resource "tfe_variable_set" "aws_credentials" {
  name         = "AWS Credentials"
  description  = "AWS provider credentials for all workspaces"
  organization = var.tfc_organization
  global       = false
}

resource "tfe_variable" "aws_access_key" {
  key             = "AWS_ACCESS_KEY_ID"
  value           = var.aws_access_key_id
  category        = "env"
  sensitive       = true
  variable_set_id = tfe_variable_set.aws_credentials.id
}

resource "tfe_variable" "aws_secret_key" {
  key             = "AWS_SECRET_ACCESS_KEY"
  value           = var.aws_secret_access_key
  category        = "env"
  sensitive       = true
  variable_set_id = tfe_variable_set.aws_credentials.id
}

resource "tfe_workspace_variable_set" "production" {
  workspace_id    = tfe_workspace.main.id
  variable_set_id = tfe_variable_set.aws_credentials.id
}
```

## Sentinel Cost Control Policy

```python
# policy/cost-control.sentinel
import "tfplan/v2" as tfplan
import "decimal"

max_monthly_cost = decimal.new(1000)

main = rule {
    all tfplan.resource_changes as _, rc {
        rc.change.actions is ["no-op"] or
        (rc.change.after.cost_estimate.monthly_cost else decimal.new(0)) < max_monthly_cost
    }
}
```

## Team Access Controls

```hcl
resource "tfe_team" "developers" {
  name         = "developers"
  organization = var.tfc_organization
  visibility   = "organization"
}

resource "tfe_team_access" "developers_staging" {
  access       = "plan"
  team_id      = tfe_team.developers.id
  workspace_id = tfe_workspace.staging.id
}

resource "tfe_team_access" "developers_production" {
  access       = "read"
  team_id      = tfe_team.developers.id
  workspace_id = tfe_workspace.main.id
}
```

## Production Checklist

- [ ] Remote execution (not local) — consistent Terraform version, no state on developer machines
- [ ] VCS integration on main branch with trigger patterns
- [ ] Variable sets for credentials (single source of truth across workspaces)
- [ ] Sentinel policies for cost control and security compliance
- [ ] Drift detection (assessments_enabled = true)
- [ ] Team access: developers get plan on staging, read-only on production
- [ ] Separate projects per environment (production, staging, development)
- [ ] Run triggers for module dependencies (publishing module → triggers dependent workspace)

Terraform Cloud's workspace graph with run triggers is the key feature — publishing a module update automatically plans/applies all dependent workspaces in order, eliminating manual coordination.

## About This Guide

This guide is part of the Citadel Cloud Management content series covering AWS, Azure, GCP, DevSecOps, MCP Servers, and Cloud Careers. Follow our GitHub: https://github.com/kogunlowo123/citadel-cloud-management
