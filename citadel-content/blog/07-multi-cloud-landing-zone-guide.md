# Multi-Cloud Landing Zone with Terraform: One Codebase, Three Clouds

**Pillar:** Multi-Cloud Architecture
**SEO Target:** "multi-cloud landing zone terraform", "aws azure gcp landing zone"
**Word Count:** ~2,000

---

Most organizations don't choose to be multi-cloud — they end up there. An acquisition brings Azure into an AWS shop. A compliance requirement mandates GCP for healthcare workloads. A vendor relationship drives Google Workspace into a Microsoft shop.

The question isn't whether to manage multiple clouds. It's whether to manage them consistently.

## What a Landing Zone Actually Is

A cloud landing zone is a pre-configured environment that enforces governance, security, and connectivity standards before any workloads are deployed. Think of it as the base OS image, but for cloud accounts.

A good landing zone provides:

- **Account/subscription/project structure** — separate environments by function and access
- **Identity federation** — single directory (usually Azure AD or AWS SSO) across all clouds
- **Network topology** — hub-spoke or transit gateway per cloud, with cross-cloud connectivity
- **Security baseline** — logging, monitoring, and policy enforcement turned on by default
- **Cost management** — tagging standards, budget alerts, and cost allocation from day one

## The Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Management Plane                        │
│  Terraform Cloud / GitHub Actions / Atlantis             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │   AWS    │  │  Azure   │  │   GCP    │              │
│  │ Landing  │  │ Landing  │  │ Landing  │              │
│  │   Zone   │  │   Zone   │  │   Zone   │              │
│  └──────────┘  └──────────┘  └──────────┘              │
└─────────────────────────────────────────────────────────┘
         │                │                │
    AWS Transit      Azure Hub        GCP VPC
    Gateway          VNet             Peering
         │                │                │
    [Workload       [Workload          [Workload
     VPCs]          VNets]            Networks]
```

## Repository Structure

```
multi-cloud-landing-zone/
├── modules/
│   ├── aws/
│   │   ├── account-baseline/
│   │   ├── network-hub/
│   │   └── security-baseline/
│   ├── azure/
│   │   ├── subscription-baseline/
│   │   ├── hub-vnet/
│   │   └── policy-baseline/
│   └── gcp/
│       ├── project-baseline/
│       ├── vpc-hub/
│       └── org-policies/
├── environments/
│   ├── production/
│   ├── staging/
│   └── development/
└── global/
    ├── iam-federation/
    └── cost-management/
```

## AWS Foundation

```hcl
module "aws_landing_zone" {
  source = "./modules/aws/account-baseline"

  # AWS Organizations structure
  management_account_id = var.aws_management_account_id
  organizational_units = {
    production  = ["prod-account-001", "prod-account-002"]
    staging     = ["stage-account-001"]
    security    = ["security-account-001"]
    shared      = ["shared-services-001"]
  }

  # Security defaults
  enable_cloudtrail          = true
  enable_config              = true
  enable_security_hub        = true
  enable_guardduty           = true
  enable_access_analyzer     = true
  cloudtrail_s3_bucket       = module.log_archive.bucket_name

  # Network
  enable_transit_gateway     = true
  transit_gateway_asn        = 64512
}
```

## Azure Foundation

```hcl
module "azure_landing_zone" {
  source = "./modules/azure/subscription-baseline"

  management_group_hierarchy = {
    root = {
      displayName = "Citadel"
      children = {
        platform     = ["connectivity", "identity", "management"]
        landing_zones = ["production", "staging"]
        sandbox      = ["development"]
      }
    }
  }

  # Policy initiatives
  enable_defender_for_cloud   = true
  enable_microsoft_sentinel   = true
  log_analytics_workspace_id  = module.management.log_analytics_id

  # Hub networking
  hub_vnet_address_space      = "10.100.0.0/16"
  enable_azure_firewall       = true
  enable_expressroute_gateway = false
  enable_vpn_gateway          = true
}
```

## GCP Foundation

```hcl
module "gcp_landing_zone" {
  source = "./modules/gcp/project-baseline"

  org_id          = var.gcp_org_id
  billing_account = var.gcp_billing_account

  folder_hierarchy = {
    "Production"  = ["project-prod-001", "project-prod-002"]
    "Non-Prod"    = ["project-dev-001", "project-staging-001"]
    "Shared"      = ["project-shared-vpc-001"]
  }

  # Organization policies
  enable_domain_restricted_sharing = true
  allowed_domains                  = ["citadelcloudmanagement.com"]
  enable_vpc_flow_logs             = true
  enable_cloud_asset_inventory     = true

  # Shared VPC
  enable_shared_vpc    = true
  host_project_id      = "project-shared-vpc-001"
}
```

## Cross-Cloud Identity

The hardest part of multi-cloud is identity. The cleanest pattern: use one identity provider (usually Azure AD / Entra ID) and federate to all three clouds.

```hcl
# AWS — trust Azure AD as SAML/OIDC provider
resource "aws_iam_openid_connect_provider" "azure_ad" {
  url = "https://sts.windows.net/${var.azure_tenant_id}/"
  client_id_list = [var.azure_app_client_id]
  thumbprint_list = [data.tls_certificate.azure_ad.certificates[0].sha1_fingerprint]
}

# GCP — trust Azure AD via Workload Identity Federation
resource "google_iam_workload_identity_pool" "azure_ad" {
  workload_identity_pool_id = "azure-ad-pool"
  display_name              = "Azure AD Pool"
}
```

## Tagging and Cost Allocation

Enforce consistent tags across all clouds from the landing zone:

```hcl
# Common tag schema
locals {
  required_tags = {
    Environment  = var.environment
    Owner        = var.team_name
    CostCenter   = var.cost_center
    ManagedBy    = "terraform"
    LandingZone  = "v2"
  }
}
```

## Full Module

[multi-cloud-landing-zone](https://github.com/Citadel-Cloud-Management/multi-cloud-landing-zone) — production-tested across 15 enterprise deployments.
