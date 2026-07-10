# Reddit Posts

---

## Post 1: r/terraform

**Subreddit:** r/terraform

**Title:** I open-sourced 80+ Terraform modules for AWS, Azure, and GCP -- looking for feedback

**Body:**

Hey r/terraform,

I've been building production Terraform modules for the past year and decided to open-source all of them. The collection is now at 80+ modules across AWS, Azure, and GCP, and I'd appreciate feedback from this community.

**What's in the collection:**

AWS (25+ modules):
- Networking: VPC, Transit Gateway, PrivateLink, Route53, CloudFront
- Compute: EKS, ECS Fargate, EC2, Lambda, Autoscaling
- Security: Security Baseline (GuardDuty/Config/CloudTrail), WAF, KMS, Network Firewall
- Databases: RDS Aurora, DynamoDB, ElastiCache Redis, EFS
- AI/ML: Bedrock, SageMaker Studio, RAG Pipeline

Azure (18+ modules):
- Networking: Hub-Spoke, Virtual Network, Front Door, Application Gateway, Private Endpoint
- Compute: AKS (with Cilium + Workload Identity support), Container Apps, VMs
- Databases: Cosmos DB, SQL Database, PostgreSQL Flexible
- AI/ML: OpenAI Platform, AI Studio

GCP (15+ modules):
- Networking: VPC Network, Cloud Armor
- Compute: GKE, Cloud Run
- Databases: Cloud SQL, Spanner, BigQuery
- AI/ML: Vertex AI, Gemini Platform

**Design principles:**
- Security-first defaults (encryption on, public access blocked, logging enabled)
- Production-ready examples (not hello-world demos)
- Consistent variable naming across modules
- Proper input validation and output exports

**What I'm looking for:**
- Are there modules the community needs that I haven't built?
- Feedback on module structure and conventions
- Suggestions for improving reusability
- Anyone interested in contributing

Full collection: https://github.com/kogunlowo123

Happy to answer questions about any specific module. Not trying to sell anything -- these are all free and MIT licensed.

---

## Post 2: r/aws

**Subreddit:** r/aws

**Title:** Free Terraform module for AWS security baseline -- enables GuardDuty, Config, CloudTrail, and Access Analyzer in one apply

**Body:**

I got tired of setting up the same AWS security services manually in every new account, so I built a Terraform module that handles the entire baseline in one shot.

**What it does:**

One module call enables:
- **CloudTrail** -- multi-region trail with S3 logging, log file validation, KMS encryption
- **AWS Config** -- recorder, delivery channel, and managed rules for encryption/public access/IAM compliance
- **GuardDuty** -- threat detection with findings routed to SNS or EventBridge
- **IAM Access Analyzer** -- flags resources shared outside your trust boundary

Everything is encrypted with a customer-managed KMS key with automatic rotation.

**Usage is straightforward:**

```hcl
module "security_baseline" {
  source = "github.com/kogunlowo123/terraform-aws-security-baseline"

  enable_guardduty       = true
  enable_config          = true
  enable_cloudtrail      = true
  enable_access_analyzer = true
}
```

**Why I built this:**

I've audited too many AWS accounts where basic security services weren't enabled because "we'll get to it later." This module makes "later" take 5 minutes instead of a full sprint.

Module: https://github.com/kogunlowo123/terraform-aws-security-baseline

I also have related modules if you're building out a full security stack:
- WAF with managed rules and rate limiting: https://github.com/kogunlowo123/terraform-aws-waf
- KMS with auto-rotation: https://github.com/kogunlowo123/terraform-aws-kms
- Network Firewall: https://github.com/kogunlowo123/terraform-aws-network-firewall
- VPC with flow logs: https://github.com/kogunlowo123/terraform-aws-vpc-complete

All free, all open source. Would love to hear if there are features or Config rules you'd want added.

---

## Post 3: r/azure

**Subreddit:** r/azure

**Title:** Terraform module for AKS with Cilium CNI and Workload Identity -- open source

**Body:**

Sharing an AKS Terraform module I built that supports the newer Azure features that most existing modules don't handle well yet.

**Key features:**

- **Cilium CNI** -- eBPF-based networking via Azure CNI Overlay with Cilium. Better performance than kubenet, no IP exhaustion issues, native network policies, and Hubble observability.
- **Workload Identity** -- OIDC-based pod authentication to Azure services. No more aad-pod-identity DaemonSet.
- **System/User node pool separation** -- system workloads isolated from application workloads
- **Private cluster support** -- API server with private endpoint
- **Azure Monitor integration** -- Container Insights with Log Analytics

Module: https://github.com/kogunlowo123/terraform-azure-aks

**It pairs well with these other modules I maintain:**

- Hub-spoke networking with Azure Firewall and forced tunneling: https://github.com/kogunlowo123/terraform-azure-hub-spoke-network
- Key Vault with private endpoint and CSI driver integration: https://github.com/kogunlowo123/terraform-azure-key-vault
- Azure Monitor: https://github.com/kogunlowo123/terraform-azure-monitor
- Private Endpoint: https://github.com/kogunlowo123/terraform-azure-private-endpoint

**Why Cilium over the default CNI?**

Azure CNI has the IP exhaustion problem in large clusters. Kubenet is limited to 400 nodes. Cilium on Azure CNI Overlay gives you overlay networking (no IP exhaustion) with eBPF performance and built-in network policy enforcement.

If you're deploying AKS in production, especially in enterprise environments with hub-spoke networking, this module should save you some time.

All open source. Issues and PRs welcome.

---

## Post 4: r/devops

**Subreddit:** r/devops

**Title:** Built MCP servers for connecting AI assistants to AWS, Kubernetes, and Terraform -- here's what I learned

**Body:**

I've been experimenting with MCP (Model Context Protocol) servers for infrastructure automation over the past few months. Built 8 of them and open-sourced everything. Wanted to share what actually works and what's still rough.

**What MCP servers do:**

They give AI assistants structured access to your infrastructure. Instead of pasting error logs into a chat window and hoping for good advice, the AI can directly query your Kubernetes cluster, read CloudWatch metrics, or inspect your Terraform state.

**What I built:**

- **mcp-server-aws** (https://github.com/kogunlowo123/mcp-server-aws) -- read-only access to EC2, S3, Lambda, CloudWatch, IAM
- **mcp-server-kubernetes** (https://github.com/kogunlowo123/mcp-server-kubernetes) -- pod status, logs, events, deployment info
- **mcp-server-terraform** (https://github.com/kogunlowo123/mcp-server-terraform) -- state file parsing, resource dependency mapping
- **mcp-server-azure** (https://github.com/kogunlowo123/mcp-server-azure) -- Azure resource inspection
- **mcp-server-github** (https://github.com/kogunlowo123/mcp-server-github) -- repo, PR, and Actions context
- **mcp-server-devops** (https://github.com/kogunlowo123/mcp-server-devops) -- CI/CD pipeline data
- **mcp-server-database** (https://github.com/kogunlowo123/mcp-server-database) -- schema exploration and queries
- **mcp-server-vector-db** (https://github.com/kogunlowo123/mcp-server-vector-db) -- vector DB and RAG debugging

**What actually works well:**

- Incident triage with the Kubernetes MCP server. "Why is this pod failing?" with full log and event context is genuinely faster than kubectl + dashboard switching.
- Terraform state exploration. Understanding resource dependencies in large state files is much easier when you can ask questions about it.
- Cost analysis with the AWS MCP server.

**What's still rough:**

- Write operations need careful guardrails. I keep most servers read-only by default.
- Context windows fill up fast with large outputs (pod logs, full state files).
- Authentication and credential management needs more thought for team use.

Full platform: https://github.com/kogunlowo123/claude-mcp-platform

Not trying to sell anything -- genuinely interested in how other DevOps teams are approaching AI-assisted operations. What tools are you using?

---

## Post 5: r/kubernetes

**Subreddit:** r/kubernetes

**Title:** Open-source Terraform modules for EKS, AKS, and GKE -- production-ready with security defaults

**Body:**

I maintain Terraform modules for all three managed Kubernetes services and wanted to share them with the community. Each is designed for production deployments, not quick demos.

**EKS module** (https://github.com/kogunlowo123/terraform-aws-eks):
- Managed node groups with autoscaling configuration
- IRSA (IAM Roles for Service Accounts) support
- Private API server endpoint
- EKS add-ons management (CoreDNS, kube-proxy, VPC CNI, EBS CSI)
- Cluster security group configuration

**AKS module** (https://github.com/kogunlowo123/terraform-azure-aks):
- Cilium CNI via Azure CNI Overlay
- Workload Identity (OIDC-based)
- System and user node pool separation
- Private cluster support
- Azure Monitor Container Insights integration

**GKE module** (https://github.com/kogunlowo123/terraform-gcp-gke):
- Autopilot and Standard mode support
- Workload Identity Federation
- Private cluster with authorized networks
- Binary Authorization ready
- GKE-native monitoring

**Common design decisions across all three:**

1. **Node pool isolation** -- system workloads on dedicated node pools, application workloads on separate pools with appropriate taints
2. **Network policy support** -- Cilium on AKS, Calico on EKS, native on GKE
3. **Secret management integration** -- AWS Secrets Manager CSI, Azure Key Vault CSI, GCP Secret Manager
4. **Private by default** -- API servers are private, nodes are in private subnets

**Supporting modules:**

Each K8s module works well with my networking modules:
- AWS VPC: https://github.com/kogunlowo123/terraform-aws-vpc-complete
- Azure Hub-Spoke: https://github.com/kogunlowo123/terraform-azure-hub-spoke-network
- GCP VPC: https://github.com/kogunlowo123/terraform-gcp-vpc-network

And I built an MCP server for Kubernetes that gives AI assistants direct cluster access for troubleshooting: https://github.com/kogunlowo123/mcp-server-kubernetes

All modules are open source. If you're deploying managed Kubernetes and writing your own Terraform from scratch, these might save you some time. Happy to take feedback or PRs.
