---
title: "Multi-Cloud Landing Zone Architecture: AWS, Azure, and GCP with Terraform"
published: false
description: "Build a consistent multi-cloud landing zone across AWS, Azure, and GCP with Terraform for networking, identity, and security"
tags: terraform, cloud, multicloud, architecture
canonical_url:
cover_image:
---

# Multi-Cloud Landing Zone Architecture: AWS, Azure, and GCP with Terraform

> **Header Image Suggestion:** A high-level architecture diagram showing three cloud providers (AWS, Azure, GCP) connected via a central hub, each with consistent VPC/VNet structures, identity federation arrows, and a shared Terraform state management layer.

**Tags:** `#multicloud` `#terraform` `#aws` `#azure` `#devops`

---

"We're a multi-cloud company." I hear this in almost every engagement, and it usually means one of two things: either the organization has made a deliberate architectural decision to distribute workloads across providers, or different teams adopted different clouds and now someone has to make it all work together.

Either way, the challenge is the same — how do you build a consistent, secure, and manageable foundation across AWS, Azure, and GCP without tripling your operational overhead?

This article walks through a multi-cloud landing zone architecture I've been building and refining. The modules are all open source:

- [multi-cloud-landing-zone](https://github.com/kogunlowo123/multi-cloud-landing-zone) — Orchestration layer
- [terraform-aws-vpc-complete](https://github.com/kogunlowo123/terraform-aws-vpc-complete) — AWS networking
- [terraform-azure-virtual-network](https://github.com/kogunlowo123/terraform-azure-virtual-network) — Azure networking
- [terraform-gcp-vpc-network](https://github.com/kogunlowo123/terraform-gcp-vpc-network) — GCP networking

## Why Multi-Cloud (Honestly)

Let's be direct about the motivations, because the wrong reasons lead to the wrong architecture:

**Legitimate reasons:**
- Regulatory requirements (data sovereignty, provider diversification mandates in financial services)
- Best-of-breed services (GCP for ML/BigQuery, AWS for breadth, Azure for Microsoft ecosystem integration)
- M&A scenarios where acquired companies use different providers
- Negotiating leverage with cloud providers

**Questionable reasons:**
- "Avoiding vendor lock-in" (you're trading one lock-in for three)
- "High availability" (multi-region within one provider is simpler and more effective)

If you're going multi-cloud, do it with clear eyes about the operational cost. Every provider has different networking semantics, IAM models, and operational patterns. A landing zone abstracts some of this, but not all.

## Landing Zone Architecture Overview

A landing zone is the foundational infrastructure that must exist before any workloads deploy. It covers:

1. **Account/subscription/project structure** — organizational hierarchy
2. **Networking** — VPCs, VNets, subnets, connectivity
3. **Identity** — cross-cloud authentication and authorization
4. **Security baselines** — logging, monitoring, compliance policies
5. **State management** — where Terraform state lives

Here's the high-level structure:

```
multi-cloud-landing-zone/
  aws/
    organization/       # AWS Organizations, SCPs
    networking/          # VPC, Transit Gateway
    identity/            # IAM Identity Center, roles
    security/            # GuardDuty, Security Hub, Config
  azure/
    management-groups/   # Azure Management Groups, policies
    networking/          # Hub-spoke VNets, Azure Firewall
    identity/            # Azure AD, workload identity
    security/            # Defender, Sentinel
  gcp/
    organization/        # GCP Org, folders, projects
    networking/          # Shared VPC, Cloud NAT
    identity/            # Workload Identity Federation
    security/            # Security Command Center
  cross-cloud/
    connectivity/        # VPN tunnels, interconnects
    identity-federation/ # Cross-provider trust
    dns/                 # Unified DNS resolution
  shared/
    state-management/    # Remote state backends
    cicd/                # Pipeline configurations
```

## Consistent Networking Patterns

The single biggest source of multi-cloud complexity is networking. Each provider uses different terminology, different defaults, and different routing models. The goal is to create consistent patterns despite these differences.

### IP Address Planning

Before writing any Terraform, plan your CIDR allocations globally:

```
# Global CIDR Plan
10.0.0.0/8 — Reserved for cloud infrastructure

  AWS:
    10.0.0.0/12   (10.0.0.0 - 10.15.255.255)
    ├── 10.0.0.0/16  — Production VPC (eu-west-1)
    ├── 10.1.0.0/16  — Staging VPC (eu-west-1)
    ├── 10.2.0.0/16  — Development VPC (eu-west-1)
    ├── 10.4.0.0/16  — Production VPC (us-east-1)
    └── 10.5.0.0/16  — DR VPC (us-east-1)

  Azure:
    10.16.0.0/12  (10.16.0.0 - 10.31.255.255)
    ├── 10.16.0.0/16 — Hub VNet (westeurope)
    ├── 10.17.0.0/16 — Prod Spoke (westeurope)
    ├── 10.18.0.0/16 — Staging Spoke (westeurope)
    └── 10.20.0.0/16 — Prod Spoke (northeurope)

  GCP:
    10.32.0.0/12  (10.32.0.0 - 10.47.255.255)
    ├── 10.32.0.0/16 — Production VPC (europe-west1)
    ├── 10.33.0.0/16 — Staging VPC (europe-west1)
    └── 10.34.0.0/16 — Data Analytics VPC (us-central1)
```

Non-overlapping CIDRs across all three providers is a hard requirement. If CIDRs overlap, you cannot establish VPN tunnels or peering between clouds.

### AWS VPC

Using the [terraform-aws-vpc-complete](https://github.com/kogunlowo123/terraform-aws-vpc-complete) module:

```hcl
module "aws_vpc_production" {
  source = "github.com/kogunlowo123/terraform-aws-vpc-complete"

  vpc_name = "production"
  vpc_cidr = "10.0.0.0/16"
  azs      = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  public_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  application_subnets = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  data_subnets        = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  enable_dns_hostnames   = true
  enable_flow_logs       = true

  # Tag for Transit Gateway auto-association
  tags = {
    "landing-zone" = "production"
    "cloud"        = "aws"
  }
}
```

### Azure Virtual Network

Using the [terraform-azure-virtual-network](https://github.com/kogunlowo123/terraform-azure-virtual-network) module in a hub-spoke topology:

```hcl
module "azure_hub_vnet" {
  source = "github.com/kogunlowo123/terraform-azure-virtual-network"

  vnet_name           = "hub-westeurope"
  resource_group_name = azurerm_resource_group.networking.name
  location            = "westeurope"
  address_space       = ["10.16.0.0/16"]

  subnets = {
    GatewaySubnet = {
      address_prefix = "10.16.0.0/24"
    }
    AzureFirewallSubnet = {
      address_prefix = "10.16.1.0/24"
    }
    management = {
      address_prefix = "10.16.10.0/24"
    }
  }

  # Hub-specific features
  deploy_vpn_gateway     = true
  deploy_azure_firewall  = true

  tags = {
    "landing-zone" = "hub"
    "cloud"        = "azure"
  }
}

module "azure_spoke_production" {
  source = "github.com/kogunlowo123/terraform-azure-virtual-network"

  vnet_name           = "spoke-prod-westeurope"
  resource_group_name = azurerm_resource_group.networking.name
  location            = "westeurope"
  address_space       = ["10.17.0.0/16"]

  subnets = {
    application = {
      address_prefix = "10.17.1.0/24"
    }
    data = {
      address_prefix = "10.17.10.0/24"
    }
    aks = {
      address_prefix = "10.17.20.0/22"
    }
  }

  # Peer to hub
  peer_to_hub_vnet    = true
  hub_vnet_id         = module.azure_hub_vnet.vnet_id
  hub_vnet_name       = module.azure_hub_vnet.vnet_name
  hub_resource_group  = azurerm_resource_group.networking.name

  tags = {
    "landing-zone" = "production"
    "cloud"        = "azure"
  }
}
```

### GCP VPC Network

Using the [terraform-gcp-vpc-network](https://github.com/kogunlowo123/terraform-gcp-vpc-network) module:

```hcl
module "gcp_vpc_production" {
  source = "github.com/kogunlowo123/terraform-gcp-vpc-network"

  project_id   = "my-org-production"
  network_name = "production"

  # GCP uses custom subnet mode for landing zones
  auto_create_subnetworks = false

  subnets = [
    {
      subnet_name   = "application"
      subnet_ip     = "10.32.1.0/24"
      subnet_region = "europe-west1"

      secondary_ranges = [
        {
          range_name    = "gke-pods"
          ip_cidr_range = "10.32.64.0/18"
        },
        {
          range_name    = "gke-services"
          ip_cidr_range = "10.32.128.0/20"
        }
      ]
    },
    {
      subnet_name   = "data"
      subnet_ip     = "10.32.10.0/24"
      subnet_region = "europe-west1"
    }
  ]

  # Cloud NAT for private GKE nodes
  enable_cloud_nat = true
  nat_region       = "europe-west1"

  # Flow logs
  enable_flow_logs = true
  flow_log_config = {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}
```

Note how GCP handles GKE differently — pods and services use secondary IP ranges on subnets, which is conceptually different from how AWS and Azure handle Kubernetes networking. The landing zone module abstracts this, but you need to understand it for debugging.

## Cross-Cloud Connectivity

You have three options for connecting clouds:

### Option 1: Site-to-Site VPN (Cost-Effective)

```hcl
# AWS side — Customer Gateway pointing to Azure VPN Gateway
resource "aws_customer_gateway" "azure" {
  bgp_asn    = 65515  # Azure default ASN
  ip_address = module.azure_hub_vnet.vpn_gateway_public_ip
  type       = "ipsec.1"

  tags = { Name = "azure-hub-vpn" }
}

resource "aws_vpn_connection" "to_azure" {
  customer_gateway_id = aws_customer_gateway.azure.id
  transit_gateway_id  = aws_ec2_transit_gateway.main.id
  type                = "ipsec.1"

  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_dh_group_numbers      = [14]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA256"]
}
```

VPN tunnels provide encrypted connectivity at roughly $36/month per tunnel pair. Bandwidth is limited to about 1.25 Gbps per tunnel but you can aggregate multiple tunnels.

### Option 2: Cloud Interconnect (High Performance)

For workloads requiring consistent latency and higher bandwidth, use dedicated interconnects through a colocation facility:

- AWS Direct Connect
- Azure ExpressRoute
- GCP Cloud Interconnect

All three can terminate at the same colocation provider (Equinix, Megaport, etc.), creating a private "cloud exchange" for your organization. This is the pattern for latency-sensitive workloads like database replication.

### Option 3: Third-Party SD-WAN

Tools like Aviatrix or Alkira provide a unified control plane for multi-cloud networking. They abstract the VPN/interconnect complexity but add cost and another dependency.

## Identity Federation

Each cloud has its own identity system. The goal is to enable workloads in one cloud to authenticate to another without storing long-lived credentials.

### AWS to GCP (Workload Identity Federation)

A Lambda function that needs to access BigQuery:

```hcl
# GCP side — trust AWS OIDC tokens
resource "google_iam_workload_identity_pool" "aws" {
  project                   = "my-org-production"
  workload_identity_pool_id = "aws-pool"
  display_name              = "AWS Workload Pool"
}

resource "google_iam_workload_identity_pool_provider" "aws" {
  project                            = "my-org-production"
  workload_identity_pool_id          = google_iam_workload_identity_pool.aws.workload_identity_pool_id
  workload_identity_pool_provider_id = "aws-provider"
  display_name                       = "AWS Provider"

  aws {
    account_id = "123456789012"
  }
}

# Grant the AWS role access to a GCP service account
resource "google_service_account_iam_member" "aws_binding" {
  service_account_id = google_service_account.bigquery_reader.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.aws.name}/attribute.aws_role/arn:aws:sts::123456789012:assumed-role/lambda-bigquery-role"
}
```

### Azure to AWS (OIDC Federation)

An Azure DevOps pipeline that deploys to AWS:

```hcl
# AWS side — trust Azure AD tokens
resource "aws_iam_openid_connect_provider" "azure_ad" {
  url             = "https://login.microsoftonline.com/${var.azure_tenant_id}/v2.0"
  client_id_list  = [var.azure_app_client_id]
  thumbprint_list = [var.azure_ad_thumbprint]
}

resource "aws_iam_role" "azure_deployment" {
  name = "azure-devops-deployment"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.azure_ad.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${aws_iam_openid_connect_provider.azure_ad.url}:aud" = var.azure_app_client_id
          "${aws_iam_openid_connect_provider.azure_ad.url}:sub" = var.azure_service_principal_id
        }
      }
    }]
  })
}
```

No access keys. No stored secrets. The trust is based on cryptographic identity verification.

## Unified DNS Resolution

When services in AWS need to resolve Azure Private DNS zones (and vice versa), you need DNS forwarding:

```hcl
# AWS Route 53 Resolver — forward Azure private zones to Azure DNS
resource "aws_route53_resolver_rule" "azure_private" {
  domain_name          = "privatelink.database.windows.net"
  name                 = "azure-sql-private"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  target_ip {
    ip = "10.16.0.4"  # Azure DNS resolver in hub VNet
  }
}
```

This allows an application in AWS to connect to `mydb.privatelink.database.windows.net` and resolve it to the private IP of an Azure SQL instance.

## State Management

Each cloud's landing zone state should be stored in that cloud, with cross-references managed through Terraform remote state data sources:

```hcl
# In the Azure configuration, reference AWS VPC outputs
data "terraform_remote_state" "aws_networking" {
  backend = "s3"
  config = {
    bucket = "my-org-terraform-state"
    key    = "aws/networking/production.tfstate"
    region = "eu-west-1"
  }
}

# Use AWS VPC CIDR in Azure route configuration
resource "azurerm_route" "to_aws" {
  name                   = "route-to-aws"
  resource_group_name    = azurerm_resource_group.networking.name
  route_table_name       = azurerm_route_table.spoke.name
  address_prefix         = data.terraform_remote_state.aws_networking.outputs.vpc_cidr
  next_hop_type          = "VirtualNetworkGateway"
}
```

## Operational Considerations

### Cost Visibility

Tag everything with a consistent schema across all three providers:

```hcl
# Common tags applied everywhere
locals {
  common_tags = {
    "org:environment"  = "production"
    "org:team"         = "platform-engineering"
    "org:cost-center"  = "CC-4200"
    "org:managed-by"   = "terraform"
    "org:landing-zone" = "v2.1"
  }
}
```

Feed these tags into a unified cost management tool (CloudHealth, Spot.io, or even a custom BigQuery dashboard).

### Monitoring

Ship all flow logs and audit logs to a central location. I use a dedicated GCP project with BigQuery as the central log sink — it handles cross-cloud log analysis better than any cloud-native tool handles multi-cloud.

### Incident Response

Document which team owns which cloud. Multi-cloud incidents that span providers are the most challenging to diagnose. Having clear ownership boundaries prevents the "it's not my cloud" problem.

## Conclusion

A multi-cloud landing zone is a significant investment. The modules I've shared handle the networking, identity, and security foundations, but the organizational and operational patterns matter just as much as the Terraform code.

Start with one cloud done well, then extend to the second and third. Don't try to boil the ocean on day one.

The modules used in this article:

- [multi-cloud-landing-zone](https://github.com/kogunlowo123/multi-cloud-landing-zone) — Orchestration and cross-cloud configuration
- [terraform-aws-vpc-complete](https://github.com/kogunlowo123/terraform-aws-vpc-complete) — AWS VPC module
- [terraform-azure-virtual-network](https://github.com/kogunlowo123/terraform-azure-virtual-network) — Azure VNet module
- [terraform-gcp-vpc-network](https://github.com/kogunlowo123/terraform-gcp-vpc-network) — GCP VPC module

Find all my infrastructure modules at [github.com/kogunlowo123](https://github.com/kogunlowo123).

---

*Running multi-cloud infrastructure? I'd be curious to hear which pain points you've encountered and how you've solved them. Comments are open.*