---
title: "Production AWS VPC with Terraform: 5-Tier Subnets, NAT Gateways & VPC Endpoints"
published: true
description: "Stop using the default VPC. Build a production-grade 5-tier AWS VPC with Terraform: multi-AZ NAT gateways, VPC endpoints, flow logs, and network ACLs. Full module code included."
tags: aws, terraform, devops, networking
series: "Citadel Cloud Management: 100 Free Terraform Guides"
canonical_url: https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/01-production-vpc-terraform.md
cover_image: https://kogunlowo123.github.io/citadel-cloud-management/assets/images/og-default.png
---

> **This is part of the [Citadel Cloud Management](https://github.com/kogunlowo123/citadel-cloud-management) free Terraform guide library — 100+ production-ready guides, MIT licensed, no paywall.**

If you've inherited an AWS account where everything lives in the default VPC — security groups as the only network boundary, no flow logs, public IPs on database instances — this guide is for you.

## The 5-Tier Subnet Strategy

Instead of the typical public/private split, use five distinct tiers:

| Tier | Purpose | Internet Access |
|------|---------|----------------|
| **Public** | ALBs, NAT Gateways | Direct (IGW) |
| **Application** | ECS, EC2, Lambda | Outbound via NAT |
| **Data** | RDS, ElastiCache | None |
| **Cache** | Redis clusters | None |
| **Management** | Prometheus, VPN | Outbound via NAT |

## The Module

```hcl
module "vpc" {
  source = "github.com/kogunlowo123/terraform-aws-vpc-complete"

  vpc_name = "production"
  vpc_cidr = "10.0.0.0/16"
  azs      = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  public_subnets      = ["10.0.0.0/24",  "10.0.1.0/24",  "10.0.2.0/24"]
  application_subnets = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  data_subnets        = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
  cache_subnets       = ["10.0.30.0/24", "10.0.31.0/24", "10.0.32.0/24"]
  management_subnets  = ["10.0.40.0/24", "10.0.41.0/24", "10.0.42.0/24"]

  enable_nat_gateway    = true
  single_nat_gateway    = false  # One per AZ for HA
  enable_flow_logs      = true
  flow_logs_destination = "cloud-watch-logs"

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## VPC Endpoints: The Hidden Cost Saver

Every byte from EC2 → S3 through a NAT Gateway costs money. VPC endpoints eliminate that while keeping traffic off the public internet.

```hcl
vpc_endpoints = {
  s3 = {
    service         = "s3"
    service_type    = "Gateway"
    route_table_ids = module.vpc.private_route_table_ids
  }
  dynamodb = {
    service         = "dynamodb"
    service_type    = "Gateway"
    route_table_ids = module.vpc.private_route_table_ids
  }
  ssm = {
    service             = "ssm"
    service_type        = "Interface"
    subnet_ids          = module.vpc.management_subnet_ids
    private_dns_enabled = true
    security_group_ids  = [aws_security_group.vpc_endpoints.id]
  }
  ecr_api = {
    service             = "ecr.api"
    service_type        = "Interface"
    subnet_ids          = module.vpc.application_subnet_ids
    private_dns_enabled = true
    security_group_ids  = [aws_security_group.vpc_endpoints.id]
  }
  ecr_dkr = {
    service             = "ecr.dkr"
    service_type        = "Interface"
    subnet_ids          = module.vpc.application_subnet_ids
    private_dns_enabled = true
    security_group_ids  = [aws_security_group.vpc_endpoints.id]
  }
}
```

## Flow Logs with Anomaly Detection

```hcl
resource "aws_cloudwatch_log_metric_filter" "rejected_connections" {
  name           = "rejected-connections"
  pattern        = "[version, account_id, interface_id, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, start, end, action=REJECT, log_status]"
  log_group_name = aws_cloudwatch_log_group.vpc_flow_logs.name

  metric_transformation {
    name      = "RejectedConnections"
    namespace = "VPCFlowLogs"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "high_rejected_connections" {
  alarm_name          = "${var.prefix}-high-rejected-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RejectedConnections"
  namespace           = "VPCFlowLogs"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_actions       = [aws_sns_topic.network_alerts.arn]
}
```

## Production Checklist

- [ ] One NAT Gateway per AZ (`single_nat_gateway = false`)
- [ ] VPC Flow Logs enabled with CloudWatch retention
- [ ] S3 + DynamoDB Gateway endpoints (zero cost, immediate savings)
- [ ] SSM + ECR Interface endpoints (no bastion host needed)
- [ ] Data subnets with no route to internet (not even NAT)
- [ ] Network ACLs as defense-in-depth (beyond security groups)
- [ ] CloudWatch alarm on rejected connections (anomaly detection)
- [ ] `enable_dns_hostnames = true` for private hosted zones

## Full Code

The complete guide with all subnet configurations, network ACLs, security groups, and cost estimation is at:

👉 [github.com/kogunlowo123/citadel-cloud-management — Article 01](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/01-production-vpc-terraform.md)

---

*Part of 100 free production Terraform guides covering AWS, Azure, GCP, Kubernetes, DevSecOps, AI/ML, and Cloud Careers. MIT licensed. [Browse the full library →](https://github.com/kogunlowo123/citadel-cloud-management)*
