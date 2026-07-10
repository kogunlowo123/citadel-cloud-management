# YouTube Tutorial Script Outlines

---

## Video 1: "Production AWS VPC in 10 Minutes with Terraform"

**Duration:** ~5 minutes
**Target Audience:** DevOps engineers, cloud engineers, Terraform beginners-to-intermediate
**Module:** https://github.com/kogunlowo123/terraform-aws-vpc-complete

### Script Outline

**[0:00 - 0:30] Hook and Intro**

"Most VPC tutorials give you a single public subnet and call it a day. That's not production. In the next 5 minutes, I'm going to deploy a full production VPC -- public subnets, private subnets, database subnets, NAT gateways, flow logs, and VPC endpoints -- using a single Terraform module."

- Show the finished architecture diagram on screen: 3-AZ VPC with public/private/database subnet tiers, NAT gateways, route tables, flow logs
- "No clicking around the console. No 200 lines of HCL. One module call."

**[0:30 - 1:30] Problem Statement**

- Walk through what a production VPC actually needs:
  - Public subnets for load balancers (ALB, NLB)
  - Private subnets for application workloads (ECS, EKS, EC2)
  - Database subnets with no internet access (RDS, ElastiCache)
  - NAT gateways for outbound traffic from private subnets
  - VPC flow logs for network visibility and compliance
  - VPC endpoints for AWS service access without NAT costs
- "Writing all of this from scratch is about 150-200 lines of Terraform and a dozen resources to get right. Or you can use a module."

**[1:30 - 3:00] Walkthrough: The Module Code**

- Show the `main.tf` file on screen:

```hcl
module "vpc" {
  source = "github.com/kogunlowo123/terraform-aws-vpc-complete"

  name       = "production"
  cidr_block = "10.0.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets  = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = false  # One per AZ for HA
  enable_flow_logs     = true
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

- Walk through each section:
  - CIDR block sizing: why /16 gives you room to grow
  - Three subnet tiers: explain what goes where
  - NAT gateway per AZ: cost vs availability trade-off
  - Flow logs: compliance and debugging
  - DNS settings: required for private hosted zones and service discovery

**[3:00 - 4:00] Live Deploy**

- Run `terraform init` -- show provider download
- Run `terraform plan` -- highlight the resource count (subnets, route tables, NAT gateways, IGW, flow logs)
  - Point out: "All of these resources are created with proper associations and routing. That's the value of the module -- you don't need to wire route table associations manually."
- Run `terraform apply` -- show the apply completing
- Show the outputs: VPC ID, subnet IDs, NAT gateway IPs
  - "These outputs are what you feed into your EKS module, your RDS module, your ALB module. That's how modules compose."

**[4:00 - 4:30] What You'd Pair This With**

- Show how the VPC outputs feed into other modules:
  - EKS: pass `private_subnet_ids` for worker nodes
  - RDS: pass `database_subnet_ids` for the DB subnet group
  - ALB: pass `public_subnet_ids` for the load balancer
- "I have modules for all of these. Links in the description."
- Quick mention of related modules:
  - terraform-aws-eks
  - terraform-aws-rds-aurora
  - terraform-aws-alb

**[4:30 - 5:00] Wrap Up and CTA**

- "That's a production VPC in under 5 minutes. The module is open source -- link in the description."
- "If you're building on AWS, check out the full collection. I've got 25+ AWS modules covering networking, compute, security, databases, and AI/ML."
- "Star the repo if it helped. Subscribe for more Terraform content."
- On-screen: https://github.com/kogunlowo123/terraform-aws-vpc-complete
- On-screen: https://github.com/kogunlowo123

---

## Video 2: "Enterprise AKS Deployment: Complete Terraform Guide"

**Duration:** ~10 minutes
**Target Audience:** Azure engineers, platform teams, DevOps leads
**Modules:**
- https://github.com/kogunlowo123/terraform-azure-hub-spoke-network
- https://github.com/kogunlowo123/terraform-azure-aks
- https://github.com/kogunlowo123/terraform-azure-key-vault
- https://github.com/kogunlowo123/terraform-azure-monitor

### Script Outline

**[0:00 - 0:45] Hook and Intro**

"If you search for AKS Terraform tutorials, you'll find plenty that spin up a basic cluster. But enterprise AKS? Hub-spoke networking, Cilium CNI, Workload Identity, private API server, Key Vault integration, and centralized monitoring? That's a different conversation."

"In this video, I'm going to walk through a complete enterprise AKS deployment using four open-source Terraform modules. This is the architecture I deploy for production workloads."

- Show the full architecture diagram: Hub VNet with Azure Firewall, spoke VNet for AKS, private AKS cluster, Key Vault with private endpoint, Azure Monitor with Container Insights

**[0:45 - 2:30] Architecture Overview**

- Explain the hub-spoke model:
  - Hub VNet: shared services -- Azure Firewall, VPN Gateway, Bastion
  - Spoke VNet: AKS cluster, peered to hub
  - UDR on the AKS subnet routing egress through Azure Firewall
  - Private DNS zones in the hub for internal resolution

- Why this matters for enterprise:
  - Centralized egress control and logging
  - Network segmentation between workloads
  - Compliance requirement for many regulated industries
  - Cost optimization through shared networking infrastructure

- Why Cilium:
  - eBPF-based data plane -- faster than iptables
  - Native network policies without third-party controllers
  - Hubble for network observability
  - Azure CNI Overlay mode -- no IP exhaustion

- Why Workload Identity:
  - OIDC federation -- no managed identity DaemonSet
  - Per-pod identity to Azure services
  - Microsoft's recommended approach

**[2:30 - 4:30] Step 1: Hub-Spoke Network**

- Show the hub-spoke module code:

```hcl
module "network" {
  source = "github.com/kogunlowo123/terraform-azure-hub-spoke-network"

  resource_group_name = "rg-networking-prod"
  location            = "eastus2"

  hub_vnet_address_space   = ["10.0.0.0/16"]
  spoke_vnet_address_space = ["10.1.0.0/16"]

  enable_azure_firewall = true
  enable_bastion        = true

  spoke_subnets = {
    aks-system = {
      address_prefix = "10.1.1.0/24"
    }
    aks-workload = {
      address_prefix = "10.1.2.0/24"
    }
  }

  tags = {
    Environment = "production"
  }
}
```

- Explain each section:
  - Hub VNet for shared services
  - Spoke VNet for AKS with dedicated subnets
  - Azure Firewall for centralized egress
  - Bastion for secure access without public IPs
  - VNet peering is created automatically

**[4:30 - 6:30] Step 2: AKS Cluster**

- Show the AKS module code:

```hcl
module "aks" {
  source = "github.com/kogunlowo123/terraform-azure-aks"

  cluster_name        = "aks-prod-eastus2"
  resource_group_name = "rg-aks-prod"
  location            = "eastus2"

  kubernetes_version = "1.29"
  sku_tier           = "Standard"

  # Networking
  vnet_subnet_id  = module.network.spoke_subnet_ids["aks-system"]
  network_plugin  = "azure"
  network_policy  = "cilium"
  ebpf_data_plane = "cilium"

  # Identity
  enable_workload_identity = true
  enable_oidc_issuer       = true

  # Private cluster
  private_cluster_enabled = true

  # Node pools
  system_node_pool = {
    vm_size    = "Standard_D4s_v5"
    node_count = 3
    zones      = [1, 2, 3]
  }

  user_node_pools = {
    workload = {
      vm_size         = "Standard_D8s_v5"
      min_count       = 3
      max_count       = 20
      zones           = [1, 2, 3]
      subnet_id       = module.network.spoke_subnet_ids["aks-workload"]
    }
  }

  tags = {
    Environment = "production"
  }
}
```

- Walk through the key decisions:
  - Cilium via `ebpf_data_plane` -- explain the performance benefit
  - Workload Identity + OIDC issuer -- show how pods authenticate
  - Private cluster -- API server not exposed to internet
  - System vs user node pools -- why separation matters
  - Availability zones for HA

**[6:30 - 8:00] Step 3: Key Vault + Monitoring**

- Show Key Vault module with private endpoint:

```hcl
module "keyvault" {
  source = "github.com/kogunlowo123/terraform-azure-key-vault"

  name                = "kv-aks-prod"
  resource_group_name = "rg-aks-prod"
  location            = "eastus2"

  enable_private_endpoint = true
  private_endpoint_subnet_id = module.network.spoke_subnet_ids["aks-system"]

  enable_rbac_authorization = true

  tags = {
    Environment = "production"
  }
}
```

- Show Azure Monitor integration:

```hcl
module "monitoring" {
  source = "github.com/kogunlowo123/terraform-azure-monitor"

  resource_group_name = "rg-monitoring-prod"
  location            = "eastus2"

  enable_container_insights = true
  aks_cluster_id            = module.aks.cluster_id

  log_retention_days = 90

  tags = {
    Environment = "production"
  }
}
```

- Explain:
  - Private endpoint means secrets never traverse public internet
  - RBAC authorization over access policies (modern approach)
  - Container Insights for pod-level monitoring
  - 90-day log retention for compliance

**[8:00 - 9:15] Live Deploy and Verification**

- Show `terraform plan` output -- highlight the resource count (expect 40-60 resources)
- Show `terraform apply` completion
- Show the AKS cluster in Azure Portal:
  - Cilium network policy engine active
  - Workload Identity enabled
  - Private API server
  - Node pools across availability zones
- kubectl access via Bastion or VPN (no public API endpoint)
- Show Container Insights dashboard with initial metrics

**[9:15 - 10:00] Wrap Up**

- Recap the four-module stack:
  1. Hub-spoke networking
  2. AKS with Cilium + Workload Identity
  3. Key Vault with private endpoint
  4. Azure Monitor with Container Insights
- "This is a production-grade AKS deployment. Every component is open source."
- Links on screen for all four modules
- "I have 18+ Azure modules and 80+ total across AWS, Azure, and GCP. Full collection in the description."
- "If you want to see the EKS or GKE version of this, let me know in the comments."
- On-screen: https://github.com/kogunlowo123

---

## Video 3: "Building MCP Servers for DevOps"

**Duration:** ~8 minutes
**Target Audience:** DevOps engineers, SREs, platform engineers interested in AI tooling
**Modules:**
- https://github.com/kogunlowo123/claude-mcp-platform
- https://github.com/kogunlowo123/mcp-server-kubernetes
- https://github.com/kogunlowo123/mcp-server-aws
- https://github.com/kogunlowo123/mcp-server-terraform

### Script Outline

**[0:00 - 0:45] Hook and Intro**

"What if your AI assistant could kubectl into your cluster, read your CloudWatch metrics, and parse your Terraform state -- all without you copying and pasting anything?"

"That's what MCP servers enable. I've built 8 of them for infrastructure automation, and in this video I'm going to show you how they work, how to build one, and how they change the way you operate infrastructure."

- Quick demo teaser: show an AI assistant answering "why is the checkout pod crashlooping?" with real cluster data

**[0:45 - 2:15] What is MCP?**

- Model Context Protocol explained:
  - A standard created for connecting AI models to external data and tools
  - The AI sends a request -> MCP server executes it -> returns structured data
  - Think of it as a REST API designed specifically for AI consumption

- Why it matters for DevOps:
  - Eliminates context switching (no more: check dashboard -> copy error -> paste in chat -> wait for response)
  - AI gets real data, not your paraphrasing of the data
  - Structured responses mean better AI reasoning

- Show diagram: AI Assistant <-> MCP Client <-> MCP Servers (AWS, K8s, Terraform, etc.)

**[2:15 - 4:00] The MCP Server Collection**

Walk through each server with a quick demo of capabilities:

- **mcp-server-kubernetes** (https://github.com/kogunlowo123/mcp-server-kubernetes):
  - Get pod status, logs, events
  - List deployments, services, ingresses
  - Check node health and resource utilization
  - Demo: "Show me all pods in CrashLoopBackOff in the production namespace"

- **mcp-server-aws** (https://github.com/kogunlowo123/mcp-server-aws):
  - List EC2 instances, check status
  - Read S3 bucket configurations
  - Query CloudWatch metrics and alarms
  - Check security group rules
  - Demo: "What EC2 instances have public IPs in us-east-1?"

- **mcp-server-terraform** (https://github.com/kogunlowo123/mcp-server-terraform):
  - Parse state files
  - Map resource dependencies
  - Show drift between state and config
  - Demo: "What resources depend on this VPC?"

- **Other servers** (brief mentions):
  - mcp-server-azure, mcp-server-github, mcp-server-devops
  - mcp-server-database, mcp-server-vector-db

**[4:00 - 5:45] How an MCP Server Works (Technical Deep Dive)**

- Show the anatomy of an MCP server:
  - **Tools**: functions the AI can call (e.g., `get_pod_logs`, `list_ec2_instances`)
  - **Resources**: data the AI can read (e.g., cluster state, Terraform state)
  - **Prompts**: pre-built prompts for common tasks (e.g., "incident triage")

- Walk through a simple tool implementation:
  - Define the tool schema (name, description, parameters)
  - Implement the handler (the actual kubectl/AWS SDK call)
  - Return structured data (JSON that the AI can reason about)

- Show the Kubernetes MCP server's `get_pod_logs` tool:
  - Input: namespace, pod name, container (optional), tail lines
  - Execution: runs the equivalent of `kubectl logs`
  - Output: structured log data with timestamps

- Key design decisions:
  - Read-only by default -- explain why
  - Rate limiting to prevent runaway queries
  - Authentication via existing kubeconfig/AWS credentials
  - Error handling: return useful errors, not stack traces

**[5:45 - 7:00] Real-World Use Case: Incident Response**

- Walk through a live incident scenario:
  - Alert fires: "checkout-service pod OOMKilled"
  - Without MCP: check PagerDuty -> open Grafana -> find the right dashboard -> check pod status in kubectl -> read logs -> check recent deployments -> check resource limits
  - With MCP: ask the AI "What's happening with the checkout service?"

- Show the AI assistant:
  1. Calling mcp-server-kubernetes: gets pod status (OOMKilled), recent events, current resource limits
  2. Calling mcp-server-kubernetes: gets pod logs from the last restart
  3. Calling mcp-server-github: checks recent PRs merged to main
  4. Synthesizing: "The checkout-service pod was OOMKilled because memory limit is 512Mi but the pod is using 600Mi+ after PR #347 added an in-memory cache. Recommendation: increase memory limit to 1Gi or configure the cache to use Redis."

- "That took 15 seconds instead of 10 minutes of context switching."

**[7:00 - 7:30] Getting Started**

- How to set up:
  - Clone the MCP platform repo: https://github.com/kogunlowo123/claude-mcp-platform
  - Configure credentials (kubeconfig, AWS credentials, etc.)
  - Register MCP servers with your AI client
  - Start using natural language to query your infrastructure

- Security considerations:
  - Use read-only credentials to start
  - Scope access per environment (dev/staging/prod)
  - Audit all MCP server calls
  - Don't enable write operations until you have guardrails

**[7:30 - 8:00] Wrap Up**

- "MCP servers bridge the gap between AI assistants and your actual infrastructure. The 8 servers I built are all open source and ready to use."
- "If you're running Kubernetes, start with the Kubernetes MCP server. It has the most immediate impact on daily operations."
- Links on screen for all MCP server repos
- "I also maintain 80+ Terraform modules for AWS, Azure, and GCP if you need the infrastructure these servers connect to."
- "Full collection: https://github.com/kogunlowo123"
- "Subscribe if you want more content on AI-assisted DevOps and infrastructure automation."
