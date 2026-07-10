# Twitter/X Threads

---

## Thread 1: "I built 80+ open-source Terraform modules. Here's what I learned"

**Tweet 1:**
Over the past year, I built and open-sourced 80+ Terraform modules across AWS, Azure, and GCP.

Production-grade. Battle-tested. Free for everyone.

Here's what I learned building them (thread):

**Tweet 2:**
Lesson 1: Start with opinions, then make them configurable.

Every module I wrote started with strong defaults -- encryption on, public access off, logging enabled.

Then I exposed variables so teams can override when they actually need to.

Security by default > security by choice.

**Tweet 3:**
Lesson 2: Multi-cloud doesn't mean identical code.

I maintain modules for AWS, Azure, AND GCP. The patterns are the same, but the implementations are completely different.

VPC vs VNet vs VPC Network -- same concept, different APIs, different gotchas.

Stop trying to abstract away the cloud.

**Tweet 4:**
Lesson 3: The hardest part isn't writing the module. It's maintaining it.

Provider updates, deprecations, new features, breaking changes.

80+ modules means 80+ things to keep current. I underestimated this by 10x.

**Tweet 5:**
Lesson 4: README-driven development works for modules.

Before writing a single line of HCL, I write the README. What does this solve? What are the inputs? What gets created?

If I can't explain it simply, the module is too complex.

**Tweet 6:**
Lesson 5: Every module needs an opinionated example.

Not a "hello world" example. A production example.

The example should be something you'd actually deploy. That's where 90% of the value is for users.

**Tweet 7:**
Lesson 6: Naming conventions matter more than you think.

I standardized naming across all 80+ modules. Same variable names, same output patterns, same tagging structure.

Consistency across modules means teams can pick up any module and feel at home.

**Tweet 8:**
The full collection is open source:
https://github.com/kogunlowo123

AWS, Azure, GCP -- networking, compute, security, databases, AI/ML, and more.

Use them. Fork them. Contribute back. That's the whole point.

---

## Thread 2: "Stop paying for Terraform Cloud. Here are free modules for AWS/Azure/GCP"

**Tweet 1:**
You don't need to pay for premium Terraform modules.

I maintain 80+ production-grade Terraform modules -- all free, all open source.

AWS. Azure. GCP. Networking. Security. Compute. Databases. AI/ML.

Here's what's available (thread):

**Tweet 2:**
AWS modules (25+):

- VPC with full subnet topology: terraform-aws-vpc-complete
- EKS with managed node groups: terraform-aws-eks
- S3 with encryption + lifecycle: terraform-aws-s3-bucket
- RDS Aurora: terraform-aws-rds-aurora
- Lambda + API Gateway: terraform-aws-lambda

https://github.com/kogunlowo123

**Tweet 3:**
AWS Security stack:

- Security baseline (GuardDuty, Config, CloudTrail): terraform-aws-security-baseline
- WAF with managed rule groups: terraform-aws-waf
- KMS with key rotation: terraform-aws-kms
- Network Firewall: terraform-aws-network-firewall
- PrivateLink: terraform-aws-privatelink

All security-first by default.

**Tweet 4:**
Azure modules (18+):

- AKS with Cilium + Workload Identity: terraform-azure-aks
- Hub-spoke networking: terraform-azure-hub-spoke-network
- Key Vault: terraform-azure-key-vault
- Azure SQL + PostgreSQL Flexible: terraform-azure-sql-database
- Container Apps: terraform-azure-container-apps

https://github.com/kogunlowo123

**Tweet 5:**
GCP modules (15+):

- GKE with Autopilot support: terraform-gcp-gke
- VPC with shared VPC patterns: terraform-gcp-vpc-network
- Cloud SQL: terraform-gcp-cloud-sql
- BigQuery: terraform-gcp-bigquery
- Cloud Armor (WAF): terraform-gcp-cloud-armor

https://github.com/kogunlowo123

**Tweet 6:**
AI/ML modules:

- AWS Bedrock: terraform-aws-bedrock-platform
- AWS SageMaker Studio: terraform-aws-sagemaker-studio
- Azure OpenAI: terraform-azure-openai-platform
- Azure AI Studio: terraform-azure-ai-studio
- GCP Vertex AI: terraform-gcp-vertex-ai-platform
- GCP Gemini: terraform-gcp-gemini-platform

**Tweet 7:**
Why free?

Because infrastructure shouldn't have a paywall. Every team deserves production-grade modules, not just funded startups.

Use them. Star them if they help. PRs welcome.

https://github.com/kogunlowo123

---

## Thread 3: "The ultimate AWS security baseline in Terraform"

**Tweet 1:**
Most AWS accounts are insecure by default.

No GuardDuty. No Config rules. No CloudTrail. No centralized logging.

I built a single Terraform module that enables the entire AWS security baseline in one apply.

Here's what it covers (thread):

**Tweet 2:**
AWS CloudTrail -- enabled across all regions.

Multi-region trail with S3 logging, log file validation, and KMS encryption.

You can't investigate what you didn't log. This is table stakes.

https://github.com/kogunlowo123/terraform-aws-security-baseline

**Tweet 3:**
AWS Config -- continuous compliance monitoring.

The module sets up a Config recorder, delivery channel, and a set of managed rules covering:

- Encryption at rest checks
- Public access checks
- IAM policy auditing
- VPC flow log verification

**Tweet 4:**
Amazon GuardDuty -- threat detection on autopilot.

Enabled across the account with findings published to SNS or EventBridge.

GuardDuty catches things like crypto mining, compromised credentials, and unusual API calls. No tuning needed to start.

**Tweet 5:**
IAM Access Analyzer -- find unintended access.

The module creates an analyzer at the account or organization level.

It flags resources shared outside your trust zone: S3 buckets, KMS keys, IAM roles, Lambda functions.

**Tweet 6:**
Everything is encrypted with KMS by default.

CloudTrail logs, Config snapshots, GuardDuty findings -- all encrypted with a customer-managed KMS key with automatic rotation.

No plaintext audit data in your account.

**Tweet 7:**
The whole thing is one module call:

```hcl
module "security_baseline" {
  source = "github.com/kogunlowo123/terraform-aws-security-baseline"

  enable_guardduty       = true
  enable_config          = true
  enable_cloudtrail      = true
  enable_access_analyzer = true
}
```

Production security in 10 lines. Star it if it helps.

---

## Thread 4: "How to deploy AKS with Cilium and Workload Identity"

**Tweet 1:**
Azure AKS in 2026: if you're not using Cilium for networking and Workload Identity for pod auth, you're leaving performance and security on the table.

I built a Terraform module that sets up both out of the box. Here's the architecture (thread):

**Tweet 2:**
Why Cilium over kubenet or Azure CNI?

- eBPF-based networking (faster packet processing)
- Native network policies without a separate controller
- Hubble for observability built in
- No more IP exhaustion issues with overlay mode

It's the networking layer AKS should've shipped with.

**Tweet 3:**
Why Workload Identity over pod-managed identity?

- Federated credentials via OIDC -- no more aad-pod-identity DaemonSet
- Works with any Azure service that supports Entra ID auth
- No shared identity hacks
- Microsoft's recommended approach going forward

**Tweet 4:**
The module handles the hard parts:

- OIDC issuer configuration
- Cilium CNI plugin setup
- System and user node pool separation
- Azure CNI Overlay for Cilium compatibility
- Network policy engine set to Cilium

https://github.com/kogunlowo123/terraform-azure-aks

**Tweet 5:**
Pair it with the hub-spoke networking module for enterprise deployments:

- Central hub VNet with Azure Firewall
- Spoke VNet peering for AKS
- UDR for forced tunneling
- Private DNS zones for internal resolution

https://github.com/kogunlowo123/terraform-azure-hub-spoke-network

**Tweet 6:**
And for secrets, wire in Azure Key Vault with private endpoint:

- CSI driver integration for AKS
- Private endpoint so secrets never traverse the public internet
- RBAC-based access policies
- Automatic certificate rotation

https://github.com/kogunlowo123/terraform-azure-key-vault

**Tweet 7:**
Full stack in three module calls:

1. Hub-spoke network (terraform-azure-hub-spoke-network)
2. AKS with Cilium + Workload Identity (terraform-azure-aks)
3. Key Vault with private endpoint (terraform-azure-key-vault)

All open source. All production-grade.

https://github.com/kogunlowo123

---

## Thread 5: "5 Terraform modules every DevOps engineer needs"

**Tweet 1:**
If you're doing DevOps with Terraform, these 5 modules will save you hundreds of hours.

I've built and open-sourced all of them. Here's the list (thread):

**Tweet 2:**
1. VPC / Virtual Network module

Every deployment starts with networking. You need subnets, route tables, NAT gateways, and flow logs configured correctly from day one.

AWS: https://github.com/kogunlowo123/terraform-aws-vpc-complete
Azure: https://github.com/kogunlowo123/terraform-azure-virtual-network
GCP: https://github.com/kogunlowo123/terraform-gcp-vpc-network

**Tweet 3:**
2. Kubernetes cluster module

EKS, AKS, or GKE -- you need a module that handles node pools, RBAC, networking integration, and autoscaling without you stitching 15 resources together.

AWS: https://github.com/kogunlowo123/terraform-aws-eks
Azure: https://github.com/kogunlowo123/terraform-azure-aks
GCP: https://github.com/kogunlowo123/terraform-gcp-gke

**Tweet 4:**
3. Security baseline module

Enable GuardDuty, Config, CloudTrail, and IAM Access Analyzer in one shot. Don't wait for your first security incident to set this up.

https://github.com/kogunlowo123/terraform-aws-security-baseline

Azure equivalent: https://github.com/kogunlowo123/terraform-azure-security-center

**Tweet 5:**
4. KMS / Key Vault / Secret Manager module

Encryption key management is boring but critical. Automatic rotation, proper IAM policies, and audit logging should be a single module call.

AWS: https://github.com/kogunlowo123/terraform-aws-kms
Azure: https://github.com/kogunlowo123/terraform-azure-key-vault
GCP: https://github.com/kogunlowo123/terraform-gcp-secret-manager

**Tweet 6:**
5. Monitoring and observability module

CloudWatch, Azure Monitor, or GCP equivalent -- dashboards, alarms, log groups, and metric filters configured for your workloads.

AWS: https://github.com/kogunlowo123/terraform-aws-cloudwatch
Azure: https://github.com/kogunlowo123/terraform-azure-monitor

**Tweet 7:**
All 80+ modules live here: https://github.com/kogunlowo123

Networking. Compute. Security. Databases. AI/ML. Messaging. CDN.

Star the ones you use. Open issues if something's broken. PRs always welcome.

---

## Thread 6: "Building MCP servers for infrastructure automation"

**Tweet 1:**
I've been building MCP (Model Context Protocol) servers for infrastructure automation.

Think of it as giving AI assistants direct, structured access to your cloud infrastructure.

Here's what I've built and why it matters (thread):

**Tweet 2:**
What is MCP?

Model Context Protocol is a standard for connecting AI models to external tools and data sources.

Instead of the AI guessing your infrastructure state, it queries it directly -- your AWS account, your Kubernetes cluster, your Terraform state.

**Tweet 3:**
I built MCP servers for:

- AWS: https://github.com/kogunlowo123/mcp-server-aws
- Azure: https://github.com/kogunlowo123/mcp-server-azure
- Kubernetes: https://github.com/kogunlowo123/mcp-server-kubernetes
- Terraform: https://github.com/kogunlowo123/mcp-server-terraform
- GitHub: https://github.com/kogunlowo123/mcp-server-github

**Tweet 4:**
The AWS MCP server lets an AI assistant:

- List and inspect EC2 instances, S3 buckets, Lambda functions
- Check security group rules
- Read CloudWatch metrics and logs
- Query cost data

All read-only by default. You control what actions are allowed.

**Tweet 5:**
The Kubernetes MCP server is the one I use most.

- Get pod status, logs, events
- Inspect deployments, services, ingresses
- Check node health
- Read Helm release info

"Why is this pod crashing?" -- answered in seconds with full context.

https://github.com/kogunlowo123/mcp-server-kubernetes

**Tweet 6:**
The Terraform MCP server connects AI to your state files:

- Parse and query terraform state
- Understand resource dependencies
- Suggest plan changes
- Validate configurations

Pair it with the DevOps MCP server for full CI/CD context:
https://github.com/kogunlowo123/mcp-server-devops

**Tweet 7:**
I also built a database MCP server and a vector DB MCP server:

- https://github.com/kogunlowo123/mcp-server-database
- https://github.com/kogunlowo123/mcp-server-vector-db

AI-assisted database queries, schema exploration, and RAG pipeline debugging.

**Tweet 8:**
The full MCP platform is here: https://github.com/kogunlowo123/claude-mcp-platform

All servers are open source. All follow the same patterns.

Infrastructure automation is getting a massive upgrade. These tools are how you get ahead of it.

---

## Thread 7: "Multi-cloud networking: same patterns, different clouds"

**Tweet 1:**
I maintain networking modules for AWS, Azure, and GCP.

The patterns are identical. The implementations are completely different.

Here's how multi-cloud networking actually works when you stop trying to abstract it (thread):

**Tweet 2:**
The Hub-Spoke pattern:

AWS: Transit Gateway connects VPCs
Azure: Hub VNet with peering to spoke VNets
GCP: Shared VPC with host/service projects

Same architecture diagram. Three completely different resource models.

AWS: https://github.com/kogunlowo123/terraform-aws-transit-gateway
Azure: https://github.com/kogunlowo123/terraform-azure-hub-spoke-network

**Tweet 3:**
Private connectivity to services:

AWS: PrivateLink + VPC Endpoints
Azure: Private Endpoints + Private Link Service
GCP: Private Service Connect

All solve the same problem: "How do I talk to managed services without going through the public internet?"

AWS: https://github.com/kogunlowo123/terraform-aws-privatelink
Azure: https://github.com/kogunlowo123/terraform-azure-private-endpoint

**Tweet 4:**
Edge security / WAF:

AWS: WAF + CloudFront
Azure: Front Door + WAF Policy
GCP: Cloud Armor + Cloud CDN

Three different product names. Same core capability: L7 filtering at the edge.

AWS: https://github.com/kogunlowo123/terraform-aws-waf
Azure: https://github.com/kogunlowo123/terraform-azure-front-door
GCP: https://github.com/kogunlowo123/terraform-gcp-cloud-armor

**Tweet 5:**
DNS:

AWS: Route 53 (public + private hosted zones)
Azure: Azure DNS + Private DNS Zones
GCP: Cloud DNS

The tricky part is cross-cloud DNS resolution. Conditional forwarding is your friend.

https://github.com/kogunlowo123/terraform-aws-route53

**Tweet 6:**
My approach: one module per cloud, same variable interface where possible.

Don't build a "multi-cloud networking module." Build cloud-specific modules with consistent naming.

Your teams should understand the cloud they're deploying to, not hide behind abstractions that leak.

**Tweet 7:**
All networking modules: https://github.com/kogunlowo123

- terraform-aws-vpc-complete
- terraform-aws-transit-gateway
- terraform-azure-hub-spoke-network
- terraform-azure-virtual-network
- terraform-gcp-vpc-network

Star them. Use them. Break the vendor lock-in myth.

---

## Thread 8: "AWS WAF best practices in Terraform"

**Tweet 1:**
AWS WAF is one of the most under-configured services I see in production.

Default rules aren't enough. Rate limiting is usually missing. Logging goes nowhere.

I built a Terraform module that gets WAF right. Here's the architecture (thread):

**Tweet 2:**
Start with AWS Managed Rule Groups. They're free (mostly) and cover the basics:

- AWSManagedRulesCommonRuleSet (SQLi, XSS, common exploits)
- AWSManagedRulesKnownBadInputsRuleSet (Log4j, etc.)
- AWSManagedRulesSQLiRuleSet
- AWSManagedRulesLinuxRuleSet (if applicable)

The module enables these by default.

**Tweet 3:**
Add rate limiting. Always.

A blanket rate limit of 2000 req/5min per IP catches basic DDoS and credential stuffing.

Then add targeted rate limits for login/signup endpoints at a lower threshold (100-500 req/5min).

The module supports both global and URI-specific rate rules.

**Tweet 4:**
Geo-blocking when it makes sense.

If your app only serves North America and Europe, block everything else at the WAF layer. Don't waste compute on traffic you'll never serve.

The module takes a simple list of allowed country codes.

**Tweet 5:**
Logging is where most WAF setups fail.

The module ships logs to:
- CloudWatch Logs (for real-time dashboards)
- S3 (for long-term retention and compliance)
- Kinesis Firehose (for SIEM integration)

You pick the destination. Sampled requests are logged by default.

**Tweet 6:**
Associate with ALB, CloudFront, or API Gateway.

The module handles all three association types. One WAF WebACL can protect multiple resources.

Pair it with:
- https://github.com/kogunlowo123/terraform-aws-alb
- https://github.com/kogunlowo123/terraform-aws-cloudfront-cdn
- https://github.com/kogunlowo123/terraform-aws-api-gateway-v2

**Tweet 7:**
Full module: https://github.com/kogunlowo123/terraform-aws-waf

Managed rules, rate limiting, geo-blocking, IP allowlists/blocklists, custom rules, and full logging.

One module. Production WAF. No excuses.

---

## Thread 9: "Free Terraform modules for S3, KMS, VPC, EKS, and more"

**Tweet 1:**
I keep seeing teams write the same Terraform from scratch.

S3 buckets with encryption. VPCs with proper subnets. EKS clusters with managed node groups.

I've already written all of this. It's free. Here's the catalog (thread):

**Tweet 2:**
S3 Bucket -- https://github.com/kogunlowo123/terraform-aws-s3-bucket

- Server-side encryption (SSE-S3 or SSE-KMS)
- Versioning enabled by default
- Public access block enforced
- Lifecycle rules for cost optimization
- Replication support for DR

**Tweet 3:**
KMS -- https://github.com/kogunlowo123/terraform-aws-kms

- Customer managed keys with auto rotation
- Key policies with least-privilege grants
- Alias management
- Multi-region key support
- Integrates with S3, RDS, EBS, and every service that supports CMK

**Tweet 4:**
VPC -- https://github.com/kogunlowo123/terraform-aws-vpc-complete

- Public, private, and database subnets across AZs
- NAT Gateway (single or per-AZ)
- VPC Flow Logs to CloudWatch or S3
- DNS support and hostnames enabled
- VPC endpoints for S3 and DynamoDB

**Tweet 5:**
EKS -- https://github.com/kogunlowo123/terraform-aws-eks

- Managed node groups with autoscaling
- IRSA (IAM Roles for Service Accounts)
- Cluster autoscaler ready
- Private endpoint access
- Add-ons management (CoreDNS, kube-proxy, VPC CNI)

**Tweet 6:**
RDS Aurora -- https://github.com/kogunlowo123/terraform-aws-rds-aurora

- Aurora MySQL or PostgreSQL
- Multi-AZ with read replicas
- KMS encryption
- Performance Insights
- Automated backups and snapshot management

**Tweet 7:**
And there's 75+ more covering:

Compute: EC2, ECS Fargate, Lambda, Autoscaling
Networking: Transit Gateway, PrivateLink, Route53, CloudFront
Security: WAF, Network Firewall, Security Baseline
Databases: DynamoDB, ElastiCache Redis, RDS
AI/ML: Bedrock, SageMaker, Vertex AI, Azure OpenAI

All at: https://github.com/kogunlowo123

---

## Thread 10: "My open-source Terraform module collection just hit 80+ repos"

**Tweet 1:**
Milestone: my open-source Terraform module collection just crossed 80 repositories.

AWS. Azure. GCP. Plus MCP servers for AI-powered infrastructure automation.

Here's the breakdown and what's coming next (thread):

**Tweet 2:**
By the numbers:

- 25+ AWS modules
- 18+ Azure modules
- 15+ GCP modules
- 8 MCP servers
- Categories: networking, compute, security, databases, AI/ML, messaging, CDN, monitoring

Every module follows the same structure and conventions.

**Tweet 3:**
Most-used AWS modules:

1. terraform-aws-vpc-complete
2. terraform-aws-eks
3. terraform-aws-s3-bucket
4. terraform-aws-security-baseline
5. terraform-aws-ecs-fargate

These five alone replace hundreds of lines of custom HCL in most orgs.

**Tweet 4:**
Most-used Azure modules:

1. terraform-azure-aks
2. terraform-azure-hub-spoke-network
3. terraform-azure-key-vault
4. terraform-azure-virtual-network
5. terraform-azure-container-apps

The AKS module with Cilium support has been the most requested feature.

**Tweet 5:**
The AI/ML category is growing fastest:

- terraform-aws-bedrock-platform
- terraform-aws-sagemaker-studio
- terraform-azure-openai-platform
- terraform-azure-ai-studio
- terraform-gcp-vertex-ai-platform
- terraform-gcp-gemini-platform
- terraform-aws-rag-pipeline

Infrastructure for AI is the next wave of IaC.

**Tweet 6:**
The MCP servers are the most experimental but also the most exciting:

- mcp-server-aws
- mcp-server-azure
- mcp-server-kubernetes
- mcp-server-terraform
- mcp-server-github
- mcp-server-devops
- mcp-server-database
- mcp-server-vector-db

AI-assisted infrastructure management is real and it's here.

**Tweet 7:**
What's next:

- More GCP modules (Cloud Functions, Dataflow, Apigee)
- Terraform testing with terratest examples
- Module composition patterns (full stack blueprints)
- More MCP server capabilities

**Tweet 8:**
Everything is at: https://github.com/kogunlowo123

If any of these modules have saved you time, a star goes a long way. Issues and PRs are always welcome.

Building in the open is how we all get better.
