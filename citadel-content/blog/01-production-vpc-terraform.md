# Building a Production-Ready AWS VPC with Terraform: Multi-Tier Subnets, NAT Gateways, and VPC Endpoints

**Pillar:** AWS Infrastructure
**SEO Target:** "production aws vpc terraform", "terraform aws vpc multi-tier"
**Word Count:** ~2,100
**Published:** 2026-03-10

---

If you've ever inherited an AWS account where everything lives in the default VPC, you know the pain. Security groups used as the only network boundary. No flow logs. Public IP addresses on database instances. It's the kind of setup that keeps security teams awake at night.

A well-architected VPC is the foundation of everything you build on AWS. Get it wrong, and you're retrofitting network isolation into a running production system — one of the least enjoyable exercises in cloud engineering.

In this article, I'll walk through a production-grade VPC architecture using Terraform, based on a module I've been refining across multiple enterprise deployments.

## Why VPC Architecture Matters More Than You Think

Most teams start with a simple public/private subnet split and call it a day. That works for a proof of concept, but production workloads demand more:

- **Regulatory compliance** often requires network-level isolation between application tiers
- **Cost optimization** depends on keeping traffic within the AWS network via VPC endpoints
- **Blast radius reduction** means a compromised web server shouldn't have a network path to your database
- **Operational visibility** requires flow logs that actually capture meaningful traffic patterns

## The 5-Tier Subnet Strategy

Instead of the typical two-tier model, I use five distinct subnet tiers:

| Tier | Purpose | Internet Access | Example Workloads |
|------|---------|----------------|-------------------|
| **Public** | Internet-facing resources | Direct (IGW) | ALBs, NAT Gateways |
| **Application** | Compute workloads | Outbound via NAT | ECS tasks, EC2, Lambda |
| **Data** | Databases and storage | None | RDS, ElastiCache |
| **Cache** | In-memory data stores | None | Redis clusters |
| **Management** | Ops and monitoring tools | Outbound via NAT | Prometheus, VPN |

Each tier gets its own subnet in every availability zone, its own route table, and its own set of network ACLs.

```hcl
module "vpc" {
  source = "github.com/kogunlowo123/terraform-aws-vpc-complete"

  vpc_name   = "production"
  vpc_cidr   = "10.0.0.0/16"
  azs        = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  public_subnets      = ["10.0.0.0/24",  "10.0.1.0/24",  "10.0.2.0/24"]
  application_subnets = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  data_subnets        = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
  cache_subnets       = ["10.0.30.0/24", "10.0.31.0/24", "10.0.32.0/24"]
  management_subnets  = ["10.0.40.0/24", "10.0.41.0/24", "10.0.42.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false  # One per AZ for HA
  enable_vpn_gateway     = false
  enable_flow_logs       = true
  flow_logs_destination  = "cloud-watch-logs"

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## VPC Endpoints: The Hidden Cost Saver

Every byte of data that travels from an EC2 instance to S3 through a NAT Gateway costs money. VPC endpoints eliminate that cost for AWS services while also improving security by keeping traffic off the public internet.

For a production workload, I enable at minimum:

- **S3 Gateway endpoint** — eliminates NAT charges for S3 traffic
- **DynamoDB Gateway endpoint** — same benefit for DynamoDB
- **SSM Interface endpoints** — secure instance management without bastion hosts
- **ECR endpoints** — fast, private container image pulls
- **CloudWatch endpoints** — metrics and logs without internet egress

```hcl
vpc_endpoints = {
  s3 = {
    service      = "s3"
    service_type = "Gateway"
    route_table_ids = concat(
      module.vpc.application_route_table_ids,
      module.vpc.data_route_table_ids
    )
  }
  ssm = {
    service             = "ssm"
    service_type        = "Interface"
    subnet_ids          = module.vpc.application_subnet_ids
    security_group_ids  = [aws_security_group.vpc_endpoints.id]
    private_dns_enabled = true
  }
}
```

## Flow Logs and Observability

A VPC without flow logs is flying blind. Enable them from day one:

```hcl
resource "aws_flow_log" "main" {
  vpc_id          = module.vpc.vpc_id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
}
```

Store flow logs in S3 for long-term retention and cost, but stream a subset to CloudWatch Logs for real-time alerting. Athena queries on S3-stored flow logs are invaluable for security investigations.

## Network ACLs vs Security Groups

The most common mistake is relying solely on security groups. NACLs add a stateless layer of defense:

- Security groups are stateful (return traffic automatically allowed)
- NACLs are stateless (must explicitly allow inbound AND outbound)
- Use NACLs to block entire CIDR ranges at the subnet level
- Layer both for defense in depth

## Production Checklist

Before calling a VPC production-ready:

- [ ] At least 2 AZs (3 preferred) for all subnet tiers
- [ ] Flow logs enabled and retained for 90+ days
- [ ] NAT Gateways in each AZ (not a single NAT)
- [ ] S3 and DynamoDB VPC endpoints deployed
- [ ] DNS resolution and DNS hostnames enabled
- [ ] VPC CIDR sized for growth (avoid future re-addressing)
- [ ] All subnets tagged with tier and environment

## Full Module

The complete module with all these patterns: [terraform-aws-vpc-complete](https://github.com/kogunlowo123/terraform-aws-vpc-complete)

It's been used in production across financial services, healthcare, and SaaS workloads. Issues and PRs welcome.
