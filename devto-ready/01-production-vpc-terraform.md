---
title: "Building a Production-Ready AWS VPC with Terraform: Multi-Tier Subnets, NAT Gateways, and VPC Endpoints"
published: false
description: "Deploy a 5-tier AWS VPC with Terraform featuring NAT gateways, VPC endpoints, flow logs, and network ACLs for production workloads"
tags: terraform, aws, devops, cloud
canonical_url:
cover_image:
---

# Building a Production-Ready AWS VPC with Terraform: Multi-Tier Subnets, NAT Gateways, and VPC Endpoints

> **Header Image Suggestion:** A network topology diagram showing a multi-tier VPC with public, private, database, cache, and management subnets across three availability zones, with NAT gateways and VPC endpoints illustrated.

**Tags:** `#aws` `#terraform` `#networking` `#devops` `#cloud`

---

If you've ever inherited an AWS account where everything lives in the default VPC, you know the pain. Security groups used as the only network boundary. No flow logs. Public IP addresses on database instances. It's the kind of setup that keeps security teams awake at night.

A well-architected VPC is the foundation of everything you build on AWS. Get it wrong, and you're retrofitting network isolation into a running production system — one of the least enjoyable exercises in cloud engineering.

In this article, I'll walk through a production-grade VPC architecture using Terraform, based on a module I've been refining across multiple enterprise deployments. The full module is available at [terraform-aws-vpc-complete](https://github.com/kogunlowo123/terraform-aws-vpc-complete).

## Why VPC Architecture Matters More Than You Think

Most teams start with a simple public/private subnet split and call it a day. That works for a proof of concept, but production workloads demand more:

- **Regulatory compliance** often requires network-level isolation between application tiers
- **Cost optimization** depends on keeping traffic within the AWS network via VPC endpoints
- **Blast radius reduction** means a compromised web server shouldn't have a network path to your database
- **Operational visibility** requires flow logs that actually capture meaningful traffic patterns

Let's build something that addresses all of these.

## The 5-Tier Subnet Strategy

Instead of the typical two-tier model, I use five distinct subnet tiers:

| Tier | Purpose | Internet Access | Example Workloads |
|------|---------|----------------|-------------------|
| **Public** | Internet-facing resources | Direct (IGW) | ALBs, NAT Gateways, Bastion hosts |
| **Application** | Compute workloads | Outbound via NAT | ECS tasks, EC2 instances, Lambda |
| **Data** | Databases and storage | None | RDS, ElastiCache, OpenSearch |
| **Cache** | In-memory data stores | None | Redis clusters, Memcached |
| **Management** | Ops and monitoring tools | Outbound via NAT | Jenkins, Prometheus, VPN endpoints |

Each tier gets its own subnet in every availability zone, its own route table, and its own set of network ACLs.

### Defining the Network Layout

Here's how the module structures the CIDR allocation:

```hcl
module "vpc" {
  source = "github.com/kogunlowo123/terraform-aws-vpc-complete"

  vpc_name   = "production"
  vpc_cidr   = "10.0.0.0/16"
  azs        = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  # 5-tier subnet strategy
  public_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  application_subnets = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  data_subnets        = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
  cache_subnets       = ["10.0.30.0/24", "10.0.31.0/24", "10.0.32.0/24"]
  management_subnets  = ["10.0.40.0/24", "10.0.41.0/24", "10.0.42.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false  # one per AZ for HA
  enable_vpn_gateway     = false
  enable_dns_hostnames   = true
  enable_dns_support     = true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "core-infrastructure"
  }
}
```

The key design decision here is the CIDR allocation. I leave gaps between tiers (`/24` blocks starting at `.1`, `.10`, `.20`, `.30`, `.40`) so there's room to add subnets later without re-addressing. In a `/16` VPC, you have 65,536 addresses — don't be stingy with the spacing.

## NAT Gateway Strategy: Cost vs. Availability

NAT gateways are one of the most expensive networking components in AWS. Each one costs roughly $32/month plus data processing charges. With three AZs, that's nearly $100/month just for NAT — before any traffic flows.

For production, I always recommend one NAT gateway per AZ:

```hcl
# High-availability NAT configuration
enable_nat_gateway   = true
single_nat_gateway   = false
one_nat_gateway_per_az = true
```

For development and staging environments, a single NAT gateway is acceptable:

```hcl
# Cost-optimized NAT for non-production
enable_nat_gateway   = true
single_nat_gateway   = true
```

The module handles the route table associations automatically. Each private subnet's route table points to the NAT gateway in its own AZ, so if one AZ goes down, the other AZs continue to function.

### Route Table Isolation

Each subnet tier gets its own route table. This is critical — it means you can have application subnets that route through NAT while data subnets have no route to the internet at all:

```hcl
resource "aws_route_table" "data" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  # No default route — these subnets are fully isolated
  # Only VPC-local traffic (10.0.0.0/16) is routable

  tags = {
    Name = "${var.vpc_name}-data-${var.azs[count.index]}"
    Tier = "data"
  }
}
```

No NAT gateway route. No internet gateway route. The database subnets literally cannot reach the internet, and the internet cannot reach them. This is defense in depth at the network layer.

## VPC Endpoints: Keeping Traffic Private and Cheap

Every call to an AWS API from within your VPC traverses the NAT gateway by default. That means S3 downloads, CloudWatch metrics, ECR image pulls — all going out through NAT and incurring data processing charges.

VPC endpoints solve this by creating private paths to AWS services:

```hcl
# Gateway endpoints (free)
enable_s3_endpoint       = true
enable_dynamodb_endpoint = true

# Interface endpoints (cost per hour + per GB)
enable_interface_endpoints = true
interface_endpoints = [
  "ecr.api",
  "ecr.dkr",
  "ecs",
  "ecs-telemetry",
  "logs",
  "monitoring",
  "ssm",
  "ssmmessages",
  "ec2messages",
  "sts",
  "secretsmanager",
  "kms"
]
```

**Gateway endpoints** (S3 and DynamoDB) are free and should always be enabled. There's no reason not to.

**Interface endpoints** cost about $7.20/month each (in `us-east-1`), plus $0.01/GB of data processed. The math works out in your favor when you're pulling container images from ECR multiple times a day or shipping thousands of CloudWatch metrics per minute.

A cluster pulling 50GB of container images monthly from ECR through NAT costs roughly $2.25 in NAT data processing. The ECR interface endpoints cost $14.40/month. At scale, though — say 500GB — the NAT cost is $22.50 and the endpoint cost is still $14.40. The crossover point depends on your traffic patterns, but the security benefit of keeping traffic off the public internet is worth the cost regardless.

## VPC Flow Logs: Visibility Into Your Network

Flow logs are non-negotiable in production. They capture metadata about every network flow — source, destination, ports, protocol, action (accept/reject), and byte counts.

```hcl
# Flow log configuration
enable_flow_logs          = true
flow_log_destination_type = "cloud-watch-logs"
flow_log_retention_days   = 90

flow_log_cloudwatch_log_group = "/vpc/production/flow-logs"

flow_log_traffic_type = "ALL"  # capture both accepted and rejected

# Custom log format for richer data
flow_log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${az-id} $${sublocation-type} $${sublocation-id}"
```

I recommend shipping flow logs to CloudWatch Logs for real-time alerting and to S3 for long-term storage and analysis with Athena:

```hcl
# Dual destination for flow logs
enable_flow_logs_s3          = true
flow_log_s3_bucket_arn       = aws_s3_bucket.flow_logs.arn
flow_log_s3_key_prefix       = "vpc-flow-logs/production"
```

### Querying Flow Logs with Athena

Once flow logs land in S3, you can create an Athena table and run SQL queries:

```sql
-- Find rejected traffic to data subnets
SELECT srcaddr, dstaddr, dstport, protocol, action,
       SUM(bytes) as total_bytes, COUNT(*) as flow_count
FROM vpc_flow_logs
WHERE action = 'REJECT'
  AND dstaddr LIKE '10.0.2%'
  AND date = '2026/03/06'
GROUP BY srcaddr, dstaddr, dstport, protocol, action
ORDER BY flow_count DESC
LIMIT 20;
```

This is how you catch misconfigured security groups, unexpected traffic patterns, and potential intrusion attempts.

## Network ACLs: The Second Layer

Security groups are stateful and operate at the instance level. Network ACLs are stateless and operate at the subnet level. Using both gives you defense in depth:

```hcl
# Data tier NACLs - restrict to only application tier
data_subnet_nacl_rules = {
  inbound = [
    {
      rule_number = 100
      protocol    = "tcp"
      action      = "allow"
      cidr_block  = "10.0.10.0/24"  # app subnet AZ-a
      from_port   = 5432
      to_port     = 5432
    },
    {
      rule_number = 101
      protocol    = "tcp"
      action      = "allow"
      cidr_block  = "10.0.11.0/24"  # app subnet AZ-b
      from_port   = 5432
      to_port     = 5432
    },
    {
      rule_number = 102
      protocol    = "tcp"
      action      = "allow"
      cidr_block  = "10.0.12.0/24"  # app subnet AZ-c
      from_port   = 5432
      to_port     = 5432
    }
  ]
  outbound = [
    {
      rule_number = 100
      protocol    = "tcp"
      action      = "allow"
      cidr_block  = "10.0.10.0/0"
      from_port   = 1024
      to_port     = 65535
    }
  ]
}
```

This ensures that even if someone misconfigures a security group, the database subnets only accept PostgreSQL traffic from the application tier.

## Tagging Strategy for Cost Allocation

Every subnet, route table, NAT gateway, and endpoint gets tagged consistently:

```hcl
subnet_tags = {
  "kubernetes.io/cluster/production" = "shared"
}

public_subnet_tags = {
  "kubernetes.io/role/elb" = "1"
  Tier                     = "public"
}

application_subnet_tags = {
  "kubernetes.io/role/internal-elb" = "1"
  Tier                              = "application"
}
```

These tags serve double duty: they enable Kubernetes auto-discovery of subnets for load balancers, and they allow cost allocation reports to break down networking costs by tier.

## Putting It All Together

Here's a complete example that ties everything together:

```hcl
module "vpc" {
  source = "github.com/kogunlowo123/terraform-aws-vpc-complete"

  vpc_name = "production"
  vpc_cidr = "10.0.0.0/16"
  azs      = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  # Subnet tiers
  public_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  application_subnets = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  data_subnets        = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
  cache_subnets       = ["10.0.30.0/24", "10.0.31.0/24", "10.0.32.0/24"]
  management_subnets  = ["10.0.40.0/24", "10.0.41.0/24", "10.0.42.0/24"]

  # NAT
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  # VPC Endpoints
  enable_s3_endpoint       = true
  enable_dynamodb_endpoint = true
  enable_interface_endpoints = true
  interface_endpoints = ["ecr.api", "ecr.dkr", "logs", "monitoring", "ssm", "sts", "kms"]

  # Flow Logs
  enable_flow_logs       = true
  flow_log_traffic_type  = "ALL"
  flow_log_retention_days = 90

  # DNS
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Lessons Learned

After deploying this pattern across dozens of AWS accounts, here are the things that consistently trip teams up:

1. **Don't use /16 for everything.** If you ever need VPC peering or Transit Gateway, overlapping CIDRs will block you. Plan your IP address space across all accounts upfront.

2. **Enable flow logs from day one.** Retroactively enabling them means you have no baseline to compare against when something goes wrong.

3. **Test failover.** Kill a NAT gateway and verify that the AZ-local route table doesn't send traffic to a NAT in another AZ. If it does, your route table associations are wrong.

4. **Review VPC endpoint policies.** An S3 gateway endpoint with a default policy allows access to every S3 bucket in every AWS account. Lock it down to your buckets.

5. **Monitor NAT gateway metrics.** `BytesOutToDestination` and `PacketsDropCount` will tell you when you're approaching throughput limits (45 Gbps per gateway).

## Wrapping Up

A production VPC isn't just about creating subnets. It's about building a network foundation that enforces security boundaries, optimizes costs, and provides the visibility you need when things go wrong at 3 AM.

The module I've walked through here is available on GitHub. Fork it, adapt it, and build on it:

- [terraform-aws-vpc-complete](https://github.com/kogunlowo123/terraform-aws-vpc-complete) — The full VPC module with all configurations discussed in this article

Check out my other infrastructure modules at [github.com/kogunlowo123](https://github.com/kogunlowo123) for complementary resources covering WAF, AKS, and multi-cloud landing zones.

---

*Have questions about VPC design or want to share your own patterns? Drop a comment below — I'd love to hear how other teams approach this.*