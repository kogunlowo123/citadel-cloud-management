# Social Distribution Batch 001 — Week of 2026-07-07

Generated: 2026-07-10
Status: Ready to distribute

---

## Twitter/X Threads

### Thread 1: MCP Servers for DevOps (Post Mon Jul 13, 15:00 CDT)

> 1/ I built 8 MCP servers that let AI assistants run Terraform, query Kubernetes, inspect AWS resources, and more. Here's what they can do: 🧵

> 2/ mcp-server-terraform: Run `terraform plan` and get a plain-English summary of what will change. Run `terraform apply` and monitor the output. No more terminal-switching.

> 3/ mcp-server-aws: Ask Claude "which EC2 instances are running without tags?" and get a real answer in seconds. Queries CloudWatch, EC2, S3, Lambda, IAM — all in one conversation.

> 4/ mcp-server-kubernetes: "Show me all pods that have been restarting in the last hour" → real data, ranked by restart count, with log excerpts. This is what K8s debugging should feel like.

> 5/ mcp-server-github: List PRs, create issues, search code, trigger workflows — from Claude Desktop. I use this daily for code reviews.

> 6/ Combined incident response example:
> - CloudWatch alert fires
> - Ask Claude to diagnose
> - It queries AWS metrics, K8s logs, Terraform state
> - Proposes a fix with a Terraform plan
> - You approve and it applies
> All without leaving the conversation.

> 7/ All 8 servers are open source under Citadel-Cloud-Management on GitHub. Setup takes ~5 minutes. Full guide in comments. 👇
> https://github.com/Citadel-Cloud-Management

---

### Thread 2: AWS VPC Design (Post Wed Jul 15, 16:00 CDT)

> 1/ Most AWS teams use a 2-tier VPC (public/private). Production workloads need 5 tiers. Here's why and how to set it up with Terraform: 🧵

> 2/ The 5 tiers:
> - Public: Internet-facing (ALBs, NAT Gateways)
> - Application: Compute (ECS, EC2)
> - Data: Databases (RDS, ElastiCache)
> - Cache: In-memory (Redis)
> - Management: Ops tools (monitoring, VPN)

> 3/ Without Data and Cache subnets, your database is one compromised web server away from direct access. With separate subnets + NACLs: no network path exists even with zero-trust bypassed.

> 4/ VPC endpoints are the hidden cost saver. S3 Gateway endpoint eliminates NAT Gateway charges for S3 traffic. For high-volume workloads this can save $500+/month.

> 5/ Flow logs are non-negotiable. Enable from day 1. Store in S3 for 90 days. Query with Athena. When you need them for a security investigation, they're already there.

> 6/ Full Terraform module: github.com/kogunlowo123/terraform-aws-vpc-complete
> Used in production across financial services, healthcare, and SaaS workloads.

---

## LinkedIn Posts

### Post 1: Multi-Cloud Landing Zones (Post Tue Jul 14, 12:00 CDT)

Most organizations don't choose to be multi-cloud — they end up there.

An acquisition brings Azure into an AWS shop. A compliance requirement mandates GCP for healthcare workloads. Suddenly you have three clouds, three billing portals, three different approaches to IAM, and no consistent governance.

A multi-cloud landing zone solves this. It's a pre-configured environment that enforces governance, security, and connectivity standards before any workloads deploy.

What a good landing zone provides:
• Account/subscription/project structure
• Identity federation across all clouds
• Network topology with cross-cloud connectivity
• Security baseline turned on by default
• Tagging standards and cost allocation from day one

The key principle: identical standards, cloud-native implementation. The governance logic is the same on AWS, Azure, and GCP. The Terraform modules are different because each cloud works differently.

Full open-source implementation: github.com/Citadel-Cloud-Management/multi-cloud-landing-zone

Used it across 15 enterprise deployments. Happy to answer questions in the comments.

#multicloud #terraform #aws #azure #gcp #cloudarchitecture #devops

---

### Post 2: Cloud Career in Africa (Post Thu Jul 16, 12:00 CDT)

Cloud engineering has become one of the most geography-independent technical careers.

An AWS Solutions Architect – Professional certification carries the same weight whether you earned it in Lagos, Nairobi, Johannesburg, or New York.

The path that's working for engineers I know in Africa:

Month 1-2: AWS Cloud Practitioner + SAA-C03 study
Month 3-5: Pass SAA-C03 + build 2 portfolio projects on GitHub
Month 6: Start applying to remote roles
Month 7-9: Terraform Associate + expand portfolio
Month 10-12: First remote contract or full-time cloud role

The biggest mistake: studying forever and never applying. Start applying when you have the SAA-C03 and two portfolio projects. You'll learn more from the interview process than from another month of studying.

I wrote a complete guide at: github.com/Citadel-Cloud-Management/cloud-career-guide-africa

Includes salary data, companies that hire remotely from Africa, and payment setup (Deel, Wise, Payoneer).

#cloudcomputing #aws #africaintech #remotework #careeradvice #terraform

---

## Reddit Posts

### r/Terraform — MCP Servers Post (Post Tue Jul 14, 15:00 CDT)

**Title:** I built MCP servers for Terraform, AWS, Kubernetes, and GitHub so Claude can manage infrastructure. Here's what it can do.

After spending too much time switching between terminals and dashboards, I built a suite of MCP (Model Context Protocol) servers that let Claude Desktop interact with cloud infrastructure directly.

**What they do:**

- **mcp-server-terraform**: Run terraform plan/apply from Claude. The AI explains what will change in plain English before applying.
- **mcp-server-aws**: Query EC2, S3, Lambda, CloudWatch, IAM without leaving the conversation.
- **mcp-server-kubernetes**: Get pod logs, scale deployments, check resource status.
- **mcp-server-github**: Manage PRs, issues, and workflows.

**Real incident response flow:**
1. CloudWatch alert fires
2. "Claude, what's wrong with production?" 
3. It queries CloudWatch metrics, K8s logs, Terraform state
4. "I think the issue is memory limits are too low. Here's the Terraform plan to fix it."
5. You approve, it applies

All open source at: https://github.com/Citadel-Cloud-Management

Setup: `npm install && npm run build`, add to `.claude.json`, restart Claude.

Happy to answer setup questions or discuss the architecture.

---

## Dev.to Article Reminder

Schedule to post these articles on Dev.to this week:

- Monday: "MCP Servers for DevOps: Complete Guide" (citadel-content/blog/06)
- Wednesday: "AWS WAF v2 with Terraform" (citadel-content/blog/13)
- Friday: "Building Production AI Agents on AWS Bedrock" (citadel-content/blog/09)

Add tags: #devops #terraform #aws #ai #mcp

Best post time: 14:00 UTC (Monday gives highest engagement)
