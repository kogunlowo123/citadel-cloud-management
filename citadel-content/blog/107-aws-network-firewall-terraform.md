# AWS Network Firewall with Terraform: Stateful Deep Packet Inspection for Production VPCs

**Pillar:** DevSecOps
**SEO Target:** aws network firewall terraform stateful inspection vpc production
**Word Count:** ~2000

AWS Network Firewall is a managed stateful firewall and intrusion prevention service that runs inside your VPC. Unlike security groups (which operate at the ENI level and are stateless by default) or NACLs (stateless, CIDR-only), Network Firewall gives you Suricata-compatible deep packet inspection, domain-based filtering, TLS SNI matching, and protocol anomaly detection — all without managing EC2-based appliances. This guide deploys a complete production inspection architecture: stateless and stateful rule groups, domain allow/deny lists, firewall endpoint routing, CloudWatch log delivery, and Transit Gateway integration for centralized north-south and east-west inspection.

## Architecture Overview

Network Firewall deploys into dedicated firewall subnets — one per Availability Zone. Traffic from workload subnets is routed to the firewall endpoint for that AZ before it reaches the internet gateway or a Transit Gateway. The firewall endpoint acts as an invisible bump-in-the-wire: accepted traffic exits the other side unchanged; dropped traffic is logged and discarded.

```
Spoke VPC (workloads)
    │
    ▼
Transit Gateway
    │
    ▼
Inspection VPC
  ┌─────────────────────────────────────┐
  │  Firewall Subnet AZ-a               │
  │  ┌─────────────────────────────┐   │
  │  │  Network Firewall Endpoint  │   │
  │  │  (stateless → stateful)     │   │
  │  └─────────────────────────────┘   │
  │  Firewall Subnet AZ-b               │
  │  ┌─────────────────────────────┐   │
  │  │  Network Firewall Endpoint  │   │
  │  └─────────────────────────────┘   │
  └─────────────────────────────────────┘
    │
    ▼
Internet Gateway / NAT Gateway
```

Each packet hits the stateless engine first. Stateless rules do fast 5-tuple matching and either drop, pass, or forward to the stateful engine. The stateful engine applies Suricata rules and domain lists with full connection state tracking. The inspection VPC pattern with Transit Gateway lets you enforce the same policy across all spoke VPCs from a single firewall fleet.

## Rule Group Types

Understanding the three rule group types before writing any HCL prevents misconfiguration:

| Rule Group Type | Engine | Matching Capability | State | Use Case |
|----------------|--------|---------------------|-------|----------|
| **Stateless** | Stateless | 5-tuple (src/dst IP, src/dst port, protocol) | None | Fast pass/drop/forward decisions on IP ranges and protocols |
| **Stateful — Suricata** | Stateful | DPI: payload, headers, TLS SNI, protocol anomalies | Full connection tracking | IPS rules, protocol enforcement, CVE signatures |
| **Stateful — Domain List** | Stateful | HTTP Host header and TLS SNI | Connection-level | Allowlist or denylist by FQDN |

All three types can coexist in a single firewall policy. Stateless rules run first at line rate; stateful rules add latency proportional to ruleset complexity, typically sub-millisecond for rule groups under 2,000 rules.

## Inspection VPC and Firewall Subnets

Firewall subnets need only a /28 — each firewall endpoint consumes one IP per AZ. Keep these subnets dedicated; do not place workloads in them.

```hcl
resource "aws_vpc" "inspection" {
  cidr_block           = "100.64.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.prefix}-inspection-vpc" })
}

resource "aws_subnet" "firewall" {
  for_each = {
    "${var.region}a" = "100.64.0.0/28"
    "${var.region}b" = "100.64.0.16/28"
    "${var.region}c" = "100.64.0.32/28"
  }

  vpc_id            = aws_vpc.inspection.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(var.tags, {
    Name = "${var.prefix}-firewall-${each.key}"
  })
}
```

## Stateless Rule Group

Stateless rules run before the stateful engine and operate at line rate. The most common production pattern is to forward all TCP and UDP traffic to the stateful engine (`aws:forward_to_sfe`), pass ICMP directly, and drop everything else including IP fragments that cannot be reassembled.

```hcl
resource "aws_networkfirewall_rule_group" "stateless_forward" {
  name     = "${var.prefix}-stateless-forward"
  type     = "STATELESS"
  capacity = 100

  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          priority = 10
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              protocols = [6] # TCP
              source {
                address_definition = "0.0.0.0/0"
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
            }
          }
        }

        stateless_rule {
          priority = 20
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              protocols = [17] # UDP
              source {
                address_definition = "0.0.0.0/0"
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
            }
          }
        }

        stateless_rule {
          priority = 30
          rule_definition {
            actions = ["aws:pass"]
            match_attributes {
              protocols = [1] # ICMP
              source {
                address_definition = "0.0.0.0/0"
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
            }
          }
        }
      }
    }
  }

  tags = var.tags
}
```

The `stateless_fragment_default_actions = ["aws:drop"]` setting in the firewall policy (see below) drops IP fragments that cannot be matched — this blocks a class of evasion techniques that split attack payloads across fragments.

## Stateful Rule Group — Suricata IPS Rules

Stateful rule groups in Suricata format give you full IPS capability: payload inspection, protocol anomaly detection, and signature-based threat blocking. Use `STRICT_ORDER` rule evaluation so rules execute in explicit priority order and a `drop` action terminates processing.

```hcl
resource "aws_networkfirewall_rule_group" "stateful_ips" {
  name     = "${var.prefix}-stateful-ips"
  type     = "STATEFUL"
  capacity = 1000

  rule_group {
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }

    rules_source {
      rules_string = <<-SURICATA
        # Block Log4Shell exploitation in HTTP headers and URIs (CVE-2021-44228)
        drop http any any -> any any (msg:"ET EXPLOIT Log4j RCE Attempt"; \
          http.header; content:"${jndi:"; nocase; \
          priority:1; sid:1000001; rev:2;)

        drop http any any -> any any (msg:"ET EXPLOIT Log4j RCE URI"; \
          http.uri; content:"${jndi:"; nocase; \
          priority:1; sid:1000002; rev:2;)

        # Block outbound SMB — ransomware lateral movement / WannaCry
        drop tcp any any -> any 445 \
          (msg:"Block Outbound SMB Port 445"; \
          priority:1; sid:1000010; rev:1;)

        drop tcp any any -> any 139 \
          (msg:"Block Outbound NetBIOS Port 139"; \
          priority:1; sid:1000011; rev:1;)

        # Block connections to common reverse-shell and C2 ports
        drop tcp any any -> any [4444,4445,1234,31337,6666,6667] \
          (msg:"Block Common Reverse Shell Ports"; \
          priority:1; sid:1000020; rev:1;)

        # Block outbound SMTP from non-mail servers (spam / phishing exfil)
        drop tcp any any -> any 25 \
          (msg:"Block Direct Outbound SMTP"; \
          flow:to_server,established; \
          priority:2; sid:1000030; rev:1;)

        # Detect DNS tunneling — unusually long DNS query labels
        drop dns any any -> any any \
          (msg:"Possible DNS Tunneling - Long Label"; \
          dns.query; pcre:"/[a-z0-9]{40,}\./i"; \
          priority:2; sid:1000040; rev:1;)

        # Block Tor exit node connections by protocol fingerprint
        drop tcp any any -> any [9001,9030,9050,9051] \
          (msg:"Block Tor Ports"; \
          priority:2; sid:1000050; rev:1;)

        # Pass all established sessions that survived prior rules
        pass tcp any any -> any any \
          (msg:"Pass Established TCP"; \
          flow:established; \
          priority:100; sid:1000999; rev:1;)
      SURICATA
    }
  }

  tags = var.tags
}
```

Keep capacity generous — each Suricata rule with complex `pcre` patterns consumes more capacity units than simple port matches. AWS allocates capacity at creation time; you cannot resize a rule group without replacing it.

## Domain Allow and Deny Lists

Domain list rule groups inspect the HTTP `Host` header and TLS SNI to enforce egress domain policy. This is the most operationally efficient way to control outbound HTTP/HTTPS because it requires no certificate interception.

```hcl
# DENYLIST — block known staging, tunneling, and data-exfil domains
resource "aws_networkfirewall_rule_group" "domain_denylist" {
  name     = "${var.prefix}-domain-denylist"
  type     = "STATEFUL"
  capacity = 500

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "DENYLIST"
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        targets = [
          ".torproject.org",
          ".onion",
          "pastebin.com",
          ".paste.ee",
          ".ngrok.io",
          ".ngrok-free.app",
          ".serveo.net",
          ".localhost.run",
          "requestbin.com",
          ".burpcollaborator.net",
          "interactsh.com",
          "canarytokens.org",
        ]
      }
    }
  }

  tags = var.tags
}

# ALLOWLIST — restrict production egress to known-good destinations
resource "aws_networkfirewall_rule_group" "domain_allowlist" {
  name     = "${var.prefix}-domain-allowlist"
  type     = "STATEFUL"
  capacity = 1000

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        targets = [
          ".amazonaws.com",
          ".aws.amazon.com",
          ".cloudfront.net",
          ".ecr.aws",
          "docker.io",
          "registry-1.docker.io",
          "auth.docker.io",
          ".quay.io",
          ".gcr.io",
          ".pkg.dev",
          ".github.com",
          ".githubusercontent.com",
          ".hashicorp.com",
          "releases.hashicorp.com",
          "checkpoint-api.hashicorp.com",
          ".ubuntu.com",
          ".debian.org",
          "packages.microsoft.com",
          ".datadog.com",
          ".datadoghq.com",
          ".pagerduty.com",
          ".slack.com",
          "api.opsgenie.com",
          var.corporate_egress_domain,
        ]
      }
    }
  }

  tags = var.tags
}
```

The denylist runs first in the policy (lower priority number). The allowlist combined with `stateful_default_actions = ["aws:drop_strict"]` creates an implicit deny — any domain not on the allowlist is blocked. Expand this list iteratively; start in alert-only mode for two weeks before enabling `drop_strict`.

## Firewall Policy

The policy assembles rule groups with explicit priorities. Stateless rules run in priority order; stateful groups also respect priority when `STRICT_ORDER` is configured on the policy.

```hcl
resource "aws_networkfirewall_firewall_policy" "main" {
  name = "${var.prefix}-firewall-policy"

  firewall_policy {
    # All unmatched stateless traffic goes to the stateful engine
    stateless_default_actions          = ["aws:forward_to_sfe"]
    # Drop IP fragments that can't be reassembled and matched
    stateless_fragment_default_actions = ["aws:drop"]

    stateless_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateless_forward.arn
      priority     = 100
    }

    stateful_engine_options {
      rule_order                = "STRICT_ORDER"
      stream_exception_policy   = "DROP"
    }

    # Implicit default for stateful: drop_strict fails closed on policy gaps
    stateful_default_actions = ["aws:drop_strict"]

    # Priority 100 — denylist evaluated before allowlist
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.domain_denylist.arn
      priority     = 100
    }

    # Priority 200 — IPS Suricata signatures
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful_ips.arn
      priority     = 200
    }

    # Priority 300 — egress domain allowlist (pairs with drop_strict default)
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.domain_allowlist.arn
      priority     = 300
    }
  }

  tags = var.tags
}
```

`stream_exception_policy = "DROP"` is critical for security. Without it, the firewall passes traffic when it cannot determine stream state — for example during a stateful engine restart. Setting it to `DROP` fails closed.

## Deploying the Firewall

```hcl
resource "aws_networkfirewall_firewall" "main" {
  name                = "${var.prefix}-network-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn
  vpc_id              = aws_vpc.inspection.id

  dynamic "subnet_mapping" {
    for_each = aws_subnet.firewall
    content {
      subnet_id = subnet_mapping.value.id
    }
  }

  # Production change protections — require explicit Terraform state changes
  delete_protection                 = true
  firewall_policy_change_protection = true
  subnet_change_protection          = true

  tags = var.tags
}

# Extract per-AZ endpoint IDs from firewall sync state
locals {
  firewall_endpoints = {
    for sync_state in tolist(
      aws_networkfirewall_firewall.main.firewall_status[0].sync_states
    ) :
    sync_state.availability_zone => sync_state.attachment[0].endpoint_id
  }
}
```

The three change protection flags prevent accidental policy swaps, subnet modifications, and firewall deletion through Terraform. To make a change, set the flag to `false` in the same `apply` that makes the change, then re-enable it.

## Routing Traffic Through Firewall Endpoints

This is where most production deployments get stuck. Traffic must flow from workload subnets, through the firewall endpoint in the same AZ, then to its destination. Asymmetric routing — where traffic enters through one AZ's endpoint and exits another — breaks stateful inspection. Enforce AZ symmetry through route tables.

```hcl
# Each workload subnet gets a route table that sends egress to the firewall endpoint
# in its own AZ. This prevents cross-AZ inspection traffic and maintains state.
resource "aws_route_table" "workload" {
  for_each = local.firewall_endpoints

  vpc_id = aws_vpc.inspection.id

  # All non-local traffic goes to the firewall endpoint for this AZ
  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = each.value
  }

  tags = merge(var.tags, {
    Name = "${var.prefix}-workload-rt-${each.key}"
  })
}

# Internet Gateway route table — return traffic from IGW goes to firewall endpoint
# This is required for the Gateway Route Table pattern (ingress traffic inspection)
resource "aws_route_table" "igw_ingress" {
  vpc_id = aws_vpc.inspection.id

  dynamic "route" {
    for_each = local.firewall_endpoints
    content {
      # Return each AZ's workload subnet CIDR through that AZ's endpoint
      cidr_block      = var.workload_cidr_by_az[route.key]
      vpc_endpoint_id = route.value
    }
  }

  tags = merge(var.tags, { Name = "${var.prefix}-igw-ingress-rt" })
}

# Associate the ingress route table with the Internet Gateway
resource "aws_route_table_association" "igw" {
  gateway_id     = aws_internet_gateway.main.id
  route_table_id = aws_route_table.igw_ingress.id
}
```

The Gateway Route Table (`gateway_id` in `aws_route_table_association`) is supported by Terraform but often omitted in example configurations. Without it, traffic returning from the internet bypasses the firewall on the inbound path — you only get egress inspection, not ingress.

## CloudWatch Log Delivery

Network Firewall emits two log streams: FLOW logs (connection metadata, similar to VPC Flow Logs) and ALERT logs (Suricata rule matches and drops). Send ALERT logs to CloudWatch for real-time alarming and FLOW logs to S3 for cost-effective long-term storage.

```hcl
resource "aws_cloudwatch_log_group" "firewall_alert" {
  name              = "/aws/network-firewall/${var.prefix}/alert"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.logs.arn

  tags = var.tags
}

resource "aws_s3_bucket" "firewall_flow" {
  bucket = "${var.prefix}-firewall-flow-logs-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

resource "aws_networkfirewall_logging_configuration" "main" {
  firewall_arn = aws_networkfirewall_firewall.main.arn

  logging_configuration {
    # ALERT logs → CloudWatch for real-time alarming on rule matches
    log_destination_config {
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall_alert.name
      }
    }

    # FLOW logs → S3 for cost-effective long-term retention and Athena queries
    log_destination_config {
      log_destination_type = "S3"
      log_type             = "FLOW"
      log_destination = {
        bucketName = aws_s3_bucket.firewall_flow.bucket
        prefix     = "flow-logs"
      }
    }
  }
}
```

Both log types can also target Kinesis Data Firehose if you need streaming delivery to a SIEM. The `ALERT` log format is Suricata-compatible JSON — most SIEMs parse it natively.

## Transit Gateway for Centralized Inspection

A single Network Firewall fleet inspecting traffic from all spoke VPCs reduces operational overhead and policy drift. The key is asymmetric routing tables on the Transit Gateway: spoke VPCs send all traffic to the inspection attachment; the inspection VPC's TGW route table propagates spoke CIDR ranges so return traffic reaches the right attachment.

```hcl
resource "aws_ec2_transit_gateway" "main" {
  description                     = "${var.prefix} centralized inspection TGW"
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  tags = merge(var.tags, { Name = "${var.prefix}-tgw" })
}

# Inspection VPC attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.inspection.id
  subnet_ids         = values(aws_subnet.firewall)[*].id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, { Name = "${var.prefix}-inspection-attach" })
}

# Spoke VPC attachment (repeat for each spoke)
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  for_each = var.spoke_vpcs

  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.tgw_subnet_ids

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, { Name = "${var.prefix}-${each.key}-attach" })
}

# Spoke route table — default route to inspection VPC for all spoke attachments
resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags               = merge(var.tags, { Name = "${var.prefix}-spoke-rt" })
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = aws_ec2_transit_gateway_vpc_attachment.spoke

  transit_gateway_attachment_id  = each.value.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

resource "aws_ec2_transit_gateway_route" "spoke_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# Inspection route table — routes propagated from spokes so return traffic works
resource "aws_ec2_transit_gateway_route_table" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags               = merge(var.tags, { Name = "${var.prefix}-inspection-rt" })
}

resource "aws_ec2_transit_gateway_route_table_association" "inspection" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# Propagate each spoke's routes into the inspection route table
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke" {
  for_each = aws_ec2_transit_gateway_vpc_attachment.spoke

  transit_gateway_attachment_id  = each.value.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}
```

In the inspection VPC, configure a route table for the TGW attachment subnet that sends all traffic (0.0.0.0/0) to the firewall endpoint — the same AZ routing constraint applies here. Return traffic from the firewall endpoint subnet goes back to the TGW via the default route.

## Monitoring and Alerting

CloudWatch metrics for Network Firewall are emitted per firewall per AZ. Alert on dropped packets in the stateless engine (indicates a stateless rule is dropping traffic you may not intend) and on high alert counts in the stateful engine (rule matches).

```hcl
resource "aws_cloudwatch_metric_alarm" "dropped_packets" {
  for_each = toset(keys(local.firewall_endpoints))

  alarm_name          = "${var.prefix}-firewall-dropped-${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DroppedPackets"
  namespace           = "AWS/NetworkFirewall"
  period              = 60
  statistic           = "Sum"
  threshold           = 500
  treat_missing_data  = "notBreaching"

  dimensions = {
    FirewallName     = aws_networkfirewall_firewall.main.name
    AvailabilityZone = each.key
    Engine           = "Stateful"
  }

  alarm_actions = [var.security_alerts_sns_arn]
  ok_actions    = [var.security_alerts_sns_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "firewall_unhealthy" {
  alarm_name          = "${var.prefix}-firewall-endpoint-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "HealthyEndpointCount"
  namespace           = "AWS/NetworkFirewall"
  period              = 60
  statistic           = "Average"
  threshold           = length(aws_subnet.firewall)
  treat_missing_data  = "breaching"

  dimensions = {
    FirewallName = aws_networkfirewall_firewall.main.name
  }

  alarm_actions = [var.security_alerts_sns_arn]
  tags          = var.tags
}
```

Use CloudWatch Log Insights against the ALERT log group to correlate Suricata rule matches with source IPs and develop suppression rules for known-good scanners:

```
fields @timestamp, event.src_ip, event.dest_ip, event.alert.signature_id, event.alert.signature
| filter event.event_type = "alert"
| stats count(*) as hits by event.src_ip, event.alert.signature
| sort hits desc
```

## Production Checklist

- [ ] Firewall deployed in dedicated inspection VPC with one subnet per AZ
- [ ] `delete_protection`, `subnet_change_protection`, and `firewall_policy_change_protection` all set to `true`
- [ ] `stateless_fragment_default_actions = ["aws:drop"]` — no fragment-based evasion
- [ ] `stream_exception_policy = "DROP"` — fails closed on state exceptions
- [ ] `stateful_default_actions = ["aws:drop_strict"]` — implicit deny all
- [ ] Domain denylist evaluated before domain allowlist (lower priority number)
- [ ] Suricata rule groups use `STRICT_ORDER` with explicit `pass` rules for legitimate traffic
- [ ] Gateway Route Table attached to Internet Gateway for ingress inspection
- [ ] AZ-local routing enforced — workload subnets route to the endpoint in their own AZ
- [ ] ALERT logs → CloudWatch Logs with 90-day retention and KMS encryption
- [ ] FLOW logs → S3 with lifecycle policy (Glacier after 30 days, delete after 1 year)
- [ ] CloudWatch alarms on `DroppedPackets` and `HealthyEndpointCount`
- [ ] Transit Gateway spoke route table sends 0.0.0.0/0 to inspection attachment
- [ ] TGW inspection route table propagates all spoke CIDR ranges
- [ ] Rule group capacity planned for 2x expected rule count — cannot resize in place
- [ ] Domain allowlist deployed in count-only mode for 2 weeks before enabling `drop_strict`
- [ ] Suricata rules tested in a staging environment — no firewall production day-zero

Network Firewall closes the gap that security groups and NACLs leave open: encrypted traffic inspection via SNI, Suricata-based IPS with CVE signatures, and protocol enforcement without EC2 appliance management. Combined with Transit Gateway, a single policy enforces consistent east-west and north-south inspection across every VPC in the account — without touching each VPC's security group configuration.

## About This Guide

This guide is part of the Citadel Cloud Management content series covering AWS, Azure, GCP, DevSecOps, MCP Servers, and Cloud Careers. MIT licensed — use freely. Follow our GitHub: https://github.com/kogunlowo123/citadel-cloud-management
