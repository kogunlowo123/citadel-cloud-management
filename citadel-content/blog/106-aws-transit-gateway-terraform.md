# AWS Transit Gateway with Terraform: Enterprise Hub-and-Spoke Networking

**Pillar:** AWS Infrastructure
**SEO Target:** aws transit gateway terraform hub spoke enterprise networking ram sharing
**Word Count:** ~1,800

VPC peering works fine at five VPCs. At fifty, it collapses under the weight of its own mesh. Each peering connection is non-transitive, so inter-VPC routing requires a dedicated peering link for every pair — O(n²) connections and route table entries that become unmaintainable fast.

AWS Transit Gateway (TGW) solves this with a regional managed router. Every VPC attaches once to the TGW; the TGW routes between them according to route tables you control. The result is a true hub-and-spoke topology: central control, consistent policy enforcement, and linear scaling as you add accounts and VPCs.

This guide walks through a production TGW deployment in Terraform: the gateway itself, VPC attachments, route table design, cross-account sharing via AWS RAM, inter-VPC route propagation, and CloudWatch monitoring.

## Architecture Overview

```
                    ┌─────────────────────────┐
                    │    Transit Gateway       │
                    │  (us-east-1, ASN 64512)  │
                    │                          │
                    │  ┌──────────────────┐    │
                    │  │  Production RT   │    │
                    │  │  Dev RT          │    │
                    │  │  Shared Svcs RT  │    │
                    │  └──────────────────┘    │
                    └────────┬────────────┘
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │  Prod VPC   │  │  Dev VPC    │  │ Shared Svcs │
    │ 10.0.0.0/16 │  │ 10.1.0.0/16 │  │ 10.2.0.0/16 │
    │ (Acct A)    │  │ (Acct A)    │  │  (Acct B)   │
    └─────────────┘  └─────────────┘  └─────────────┘
```

Traffic flow:
- Production VPC can reach Shared Services (DNS, secrets, monitoring endpoints)
- Production and Dev VPCs are isolated from each other by separate TGW route tables
- Shared Services VPC can respond to both but cannot initiate connections to them
- All inter-VPC traffic stays on the AWS backbone — no NAT, no internet

## Transit Gateway Resource

```hcl
resource "aws_ec2_transit_gateway" "main" {
  description                     = "Enterprise hub — ${var.environment}"
  amazon_side_asn                 = 64512
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "disable"
  vpn_ecmp_support                = "enable"
  dns_support                     = "enable"
  multicast_support               = "disable"

  tags = merge(var.tags, {
    Name = "${var.prefix}-tgw"
  })
}
```

Key decisions:
- **`default_route_table_association = "disable"`** — every attachment gets explicitly associated to a route table. Never rely on the default; it creates an implicit full mesh.
- **`default_route_table_propagation = "disable"`** — same principle. Explicit propagation only.
- **`auto_accept_shared_attachments = "disable"`** — RAM-shared attachments from other accounts must be manually accepted (or accepted via Terraform in the owner account) rather than auto-connected.
- **`amazon_side_asn`** — use a private ASN (64512–65534 or 4200000000–4294967294). This matters when you attach Site-to-Site VPNs and need deterministic BGP AS path selection.

## VPC Attachments

Each VPC that needs TGW access gets one attachment resource. The attachment spans multiple subnets (one per AZ); TGW places an ENI in each subnet and uses them for routing.

```hcl
resource "aws_ec2_transit_gateway_vpc_attachment" "production" {
  transit_gateway_id                              = aws_ec2_transit_gateway.main.id
  vpc_id                                          = var.production_vpc_id
  subnet_ids                                      = var.production_tgw_subnet_ids
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  dns_support                                     = "enable"
  ipv6_support                                    = "disable"
  appliance_mode_support                          = "disable"

  tags = merge(var.tags, {
    Name = "${var.prefix}-tgw-attach-prod"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "development" {
  transit_gateway_id                              = aws_ec2_transit_gateway.main.id
  vpc_id                                          = var.development_vpc_id
  subnet_ids                                      = var.development_tgw_subnet_ids
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  dns_support                                     = "enable"
  ipv6_support                                    = "disable"
  appliance_mode_support                          = "disable"

  tags = merge(var.tags, {
    Name = "${var.prefix}-tgw-attach-dev"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "shared_services" {
  transit_gateway_id                              = aws_ec2_transit_gateway.main.id
  vpc_id                                          = var.shared_services_vpc_id
  subnet_ids                                      = var.shared_services_tgw_subnet_ids
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  dns_support                                     = "enable"
  ipv6_support                                    = "disable"
  appliance_mode_support                          = "disable"

  tags = merge(var.tags, {
    Name = "${var.prefix}-tgw-attach-shared"
  })
}
```

Subnet sizing: TGW ENIs use /28 subnets (16 IPs, 11 usable after AWS reservations). These subnets should be dedicated — no workloads, no NAT gateways. One per AZ per VPC.

### Attachment Type Comparison

| Attachment Type | Use Case | BGP Support | Appliance Mode | Bandwidth |
|---|---|---|---|---|
| **VPC** | Internal AWS VPCs (same or cross-account) | No | Optional | Up to 50 Gbps burst |
| **VPN (Site-to-Site)** | On-premises networks over IPsec | Yes (dynamic) | No | 1.25 Gbps per tunnel |
| **Direct Connect Gateway** | Dedicated private connectivity to on-prem | Yes | No | Up to 100 Gbps |
| **TGW Peering** | Cross-region TGW connectivity | No | No | Up to 50 Gbps burst |
| **Connect (GRE)** | SD-WAN appliances via GRE over VPC attachment | Yes | No | Up to 20 Gbps |

Appliance mode is relevant when traffic flows through a stateful network appliance (firewall, IDS) in a VPC attachment. Without it, asymmetric routing across AZs can cause the appliance to drop flows it never saw the SYN for.

## Transit Gateway Route Tables

Route table design is where hub-and-spoke policy lives. The pattern: one route table per traffic isolation domain.

```hcl
# Production route table — can reach shared services
resource "aws_ec2_transit_gateway_route_table" "production" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.tags, {
    Name = "${var.prefix}-tgw-rt-production"
  })
}

# Development route table — isolated from production
resource "aws_ec2_transit_gateway_route_table" "development" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.tags, {
    Name = "${var.prefix}-tgw-rt-development"
  })
}

# Shared services route table — can reach all consumers
resource "aws_ec2_transit_gateway_route_table" "shared_services" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.tags, {
    Name = "${var.prefix}-tgw-rt-shared-services"
  })
}
```

### Route Table Associations

Association answers: "which route table does an attachment consult when it needs to forward traffic?"

```hcl
resource "aws_ec2_transit_gateway_route_table_association" "production" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

resource "aws_ec2_transit_gateway_route_table_association" "development" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.development.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.development.id
}

resource "aws_ec2_transit_gateway_route_table_association" "shared_services" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared_services.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
}
```

Each attachment is associated with exactly one route table. This is mandatory — you cannot associate an attachment to multiple route tables.

### Route Propagation

Propagation answers: "which route tables should automatically learn the CIDR of this attachment?"

```hcl
# Production attachment propagates its CIDR into the shared-services RT
# so shared services can route back to production
resource "aws_ec2_transit_gateway_route_table_propagation" "prod_to_shared_rt" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
}

# Dev attachment propagates into shared-services RT only
resource "aws_ec2_transit_gateway_route_table_propagation" "dev_to_shared_rt" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.development.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
}

# Shared services propagates into both production and development RTs
# so workload VPCs know how to reach shared services
resource "aws_ec2_transit_gateway_route_table_propagation" "shared_to_prod_rt" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared_services.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "shared_to_dev_rt" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared_services.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.development.id
}

# Production does NOT propagate into development RT — they are isolated
# Development does NOT propagate into production RT
```

After propagation, the route tables look like:

- **production-rt**: `10.2.0.0/16 → shared-services attachment`
- **development-rt**: `10.2.0.0/16 → shared-services attachment`
- **shared-services-rt**: `10.0.0.0/16 → production attachment`, `10.1.0.0/16 → development attachment`

Production and development cannot reach each other because neither propagates into the other's route table. If you need a break-glass path between them, add a static route rather than propagation — it makes the exception visible in the Terraform diff.

### Static Routes

Use static routes for blackholing RFC-1918 space you never want to traverse the TGW, or for sending specific CIDRs to an inspection VPC:

```hcl
# Blackhole any traffic destined for unallocated 10.x space
resource "aws_ec2_transit_gateway_route" "blackhole_10_x" {
  destination_cidr_block         = "10.255.0.0/16"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
  blackhole                      = true
}

# Route 0.0.0.0/0 to an inspection VPC (centralized egress)
resource "aws_ec2_transit_gateway_route" "default_to_inspection" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
}
```

## VPC Route Tables: The Other Half

The TGW route tables control what the TGW does with packets. The VPC route tables control what the VPCs do — specifically, which traffic they send to the TGW in the first place.

```hcl
# In each spoke VPC, add a route toward all internal RFC-1918 space via TGW
resource "aws_route" "prod_to_tgw_10" {
  route_table_id         = var.production_private_route_table_id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "dev_to_tgw_10" {
  route_table_id         = var.development_private_route_table_id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "shared_to_tgw_10" {
  route_table_id         = var.shared_services_private_route_table_id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}
```

If you run centralized egress (all internet-bound traffic flows through an inspection or NAT VPC attached to the TGW), also add a default route in spoke VPCs pointing to the TGW instead of a local NAT Gateway.

## Cross-Account Sharing with AWS RAM

A Transit Gateway in account A can be shared to accounts B, C, and D using AWS Resource Access Manager. The spoke accounts then create VPC attachments targeting the shared TGW ARN.

### Owner Account (Account A — Network Hub)

```hcl
resource "aws_ram_resource_share" "tgw" {
  name                      = "${var.prefix}-tgw-share"
  allow_external_principals = false  # Restrict to AWS Organization only

  tags = merge(var.tags, {
    Name = "${var.prefix}-tgw-ram-share"
  })
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.main.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# Share with entire Organization (recommended) or specific OUs
resource "aws_ram_principal_association" "org" {
  principal          = var.aws_organization_arn  # e.g. "arn:aws:organizations::123456789012:organization/o-xxxx"
  resource_share_arn = aws_ram_resource_share.tgw.arn
}
```

When `allow_external_principals = false`, RAM restricts sharing to accounts within the same AWS Organization. This is the correct default — set it to `true` only when sharing with external partners, and document the exception.

### Spoke Account (Account B)

```hcl
# Data source to find the accepted RAM share
data "aws_ram_resource_share" "tgw" {
  name           = "${var.prefix}-tgw-share"
  resource_owner = "OTHER-ACCOUNTS"

  filter {
    name   = "NameEquals"
    values = ["${var.prefix}-tgw-share"]
  }
}

# Create the VPC attachment in the spoke account, referencing the shared TGW ID
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke_b" {
  transit_gateway_id = var.shared_tgw_id  # Pass TGW ID as input from network account
  vpc_id             = aws_vpc.main.id
  subnet_ids         = aws_subnet.tgw[*].id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, {
    Name = "${var.prefix}-tgw-attach"
  })
}
```

### Accepting Attachments in the Owner Account

When a spoke account creates a VPC attachment to a shared TGW, the attachment lands in a `pendingAcceptance` state in the owner account until explicitly accepted:

```hcl
resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "spoke_b" {
  transit_gateway_attachment_id = var.spoke_b_attachment_id  # Passed via SSM or shared state

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, {
    Name  = "${var.prefix}-tgw-attach-spoke-b"
    Owner = "account-b"
  })
}

# Once accepted, associate it to the correct route table
resource "aws_ec2_transit_gateway_route_table_association" "spoke_b" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment_accepter.spoke_b.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}
```

Operationally, the owner account's Terraform workspace must be applied after the spoke account creates the attachment. Use SSM Parameter Store or Terraform remote state data sources to pass the attachment ID between workspaces without hardcoding.

## Monitoring and Observability

### VPC Flow Logs on TGW Attachments

TGW does not have its own flow logs — you capture traffic at the VPC level using VPC flow logs scoped to the TGW ENI subnets.

```hcl
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.prefix}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.logs.arn

  tags = var.tags
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.prefix}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

# Enable flow logs on each VPC — capture all traffic
resource "aws_flow_log" "production" {
  vpc_id          = var.production_vpc_id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr}"

  tags = merge(var.tags, {
    Name = "${var.prefix}-flow-log-prod"
  })
}
```

The extended log format captures `pkt-srcaddr` and `pkt-dstaddr` — the original source and destination IPs. For traffic transiting the TGW, the standard `srcaddr`/`dstaddr` fields show the TGW ENI IP, which is not useful. The packet-level fields show the actual workload IPs.

### CloudWatch Alarms for TGW Metrics

AWS publishes TGW metrics under the `AWS/TransitGateway` namespace. The most operationally relevant ones:

```hcl
resource "aws_cloudwatch_metric_alarm" "tgw_packet_drop" {
  alarm_name          = "${var.prefix}-tgw-packet-drop"
  alarm_description   = "TGW is dropping packets — likely blackhole route or attachment issue"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "PacketDropCountBlackhole"
  namespace           = "AWS/TransitGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    TransitGateway = aws_ec2_transit_gateway.main.id
  }

  alarm_actions = [var.sns_alert_topic_arn]
  ok_actions    = [var.sns_alert_topic_arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "tgw_bytes_in" {
  alarm_name          = "${var.prefix}-tgw-bytes-in-high"
  alarm_description   = "TGW ingress approaching bandwidth limits"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "BytesIn"
  namespace           = "AWS/TransitGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 40000000000  # 40 GB per 5-min period (~1.07 Gbps avg)
  treat_missing_data  = "notBreaching"

  dimensions = {
    TransitGateway = aws_ec2_transit_gateway.main.id
  }

  alarm_actions = [var.sns_alert_topic_arn]

  tags = var.tags
}
```

Key TGW metrics:

| Metric | What It Tells You | Alert Threshold |
|---|---|---|
| `PacketDropCountBlackhole` | Packets hitting a blackhole route | > 0 (any drop) |
| `PacketDropCountNoRoute` | Packets with no matching TGW route | > 0 (any drop) |
| `BytesIn` / `BytesOut` | Total bandwidth through TGW | Site-specific |
| `PacketsIn` / `PacketsOut` | Packet rate (useful for pricing estimates) | Informational |
| `BytesDropCountBlackhole` | Bytes dropped by blackhole routes | > 0 |

`PacketDropCountNoRoute` is particularly useful during migrations — it surfaces missing routes before users notice connectivity failures.

## Variables and Outputs

```hcl
variable "prefix" {
  type        = string
  description = "Naming prefix for all resources"
}

variable "environment" {
  type        = string
  description = "Deployment environment (production, staging)"
}

variable "aws_organization_arn" {
  type        = string
  description = "ARN of the AWS Organization for RAM sharing"
}

variable "production_vpc_id"          { type = string }
variable "production_tgw_subnet_ids"  { type = list(string) }
variable "development_vpc_id"         { type = string }
variable "development_tgw_subnet_ids" { type = list(string) }
variable "shared_services_vpc_id"          { type = string }
variable "shared_services_tgw_subnet_ids"  { type = list(string) }

variable "sns_alert_topic_arn" {
  type        = string
  description = "SNS topic ARN for CloudWatch alarm notifications"
}

variable "tags" {
  type    = map(string)
  default = {}
}

output "transit_gateway_id" {
  value       = aws_ec2_transit_gateway.main.id
  description = "TGW ID — pass to spoke account Terraform workspaces"
}

output "transit_gateway_arn" {
  value       = aws_ec2_transit_gateway.main.arn
  description = "TGW ARN — used in RAM resource association"
}

output "ram_resource_share_arn" {
  value       = aws_ram_resource_share.tgw.arn
  description = "RAM share ARN for accepting in spoke accounts"
}

output "production_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.production.id
}

output "development_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.development.id
}

output "shared_services_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.shared_services.id
}
```

## CIDR Planning

A Transit Gateway itself does not consume VPC address space — the ENIs placed in your dedicated TGW subnets do. Plan accordingly:

- Allocate a `/28` per AZ per VPC for TGW subnets (minimum; AWS reserves 5 IPs per subnet, leaving 11 usable for ENIs)
- Keep all VPC CIDRs non-overlapping across accounts; the TGW routing engine has no NAT capability — overlapping CIDRs cause route conflicts and will silently drop traffic
- Use a centralized IPAM (AWS IPAM or a third-party tool) to allocate and track CIDRs before provisioning any VPC

## Production Checklist

- [ ] TGW created with `default_route_table_association` and `default_route_table_propagation` both set to `disable`
- [ ] Dedicated `/28` subnets per AZ per VPC for TGW ENIs — no workloads in these subnets
- [ ] All VPC CIDR blocks are non-overlapping across all accounts in scope
- [ ] One TGW route table per isolation domain (production, development, shared services, inspection)
- [ ] Propagation matrix reviewed and documented — confirm no unintended cross-domain reachability
- [ ] Blackhole routes added for unallocated RFC-1918 space to prevent route leakage
- [ ] RAM share restricted to AWS Organization (`allow_external_principals = false`)
- [ ] Cross-account attachments use `aws_ec2_transit_gateway_vpc_attachment_accepter` — never auto-accept
- [ ] VPC flow logs enabled on all attached VPCs with extended format including `pkt-srcaddr` / `pkt-dstaddr`
- [ ] CloudWatch alarms on `PacketDropCountBlackhole` and `PacketDropCountNoRoute` with SNS notification
- [ ] TGW outputs (ID, ARN, route table IDs) stored in SSM Parameter Store for cross-workspace consumption
- [ ] Terraform state per account/workspace — never manage spoke attachments from the hub workspace
- [ ] VPN ECMP enabled if Direct Connect or Site-to-Site VPN attachments are planned
- [ ] `appliance_mode_support = "enable"` set on inspection VPC attachment if a stateful firewall is in-path

Transit Gateway is the single most impactful networking resource in a multi-account AWS environment. The investment in correct route table design at deployment time pays back every time you add a new account — a new attachment, an association, and the right propagations, and traffic flows with zero coordination across teams.

---

*MIT License — free to use, adapt, and distribute. Source: [github.com/kogunlowo123/citadel-cloud-management](https://github.com/kogunlowo123/citadel-cloud-management)*
