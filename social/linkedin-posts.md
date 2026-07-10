# LinkedIn Posts

---

## Post 1: Announcing the Module Collection

**Title:** I Open-Sourced 80+ Production-Grade Terraform Modules

Over the past year, I've been building and open-sourcing Terraform modules for AWS, Azure, and GCP. The collection has now crossed 80 repositories, and I want to share why I built them and what's inside.

The problem I kept seeing: teams spending weeks writing the same infrastructure code from scratch. VPCs with proper subnet layouts. Kubernetes clusters with security best practices. Encryption key management with rotation policies. Every team was solving the same problems independently, and most were getting it wrong the first time.

So I started codifying the patterns I've deployed in production into reusable, well-documented Terraform modules.

The collection covers:

- Networking: VPC, Transit Gateway, hub-spoke architectures, VPN, PrivateLink
- Compute: EKS, AKS, GKE, ECS Fargate, EC2, Lambda, Container Apps
- Security: WAF, security baselines, KMS, Key Vault, Network Firewall
- Databases: RDS Aurora, DynamoDB, Cosmos DB, Cloud SQL, PostgreSQL Flexible
- AI/ML: Bedrock, SageMaker, Azure OpenAI, Vertex AI, Gemini
- Monitoring: CloudWatch, Azure Monitor

Every module ships with security-first defaults. Encryption is on. Public access is off. Logging is enabled. You can override anything, but the safe path is the default path.

I also built 8 MCP (Model Context Protocol) servers for AI-assisted infrastructure management -- connecting AI tools directly to AWS, Azure, Kubernetes, Terraform, and more.

Everything is free and open source: https://github.com/kogunlowo123

If you're a DevOps engineer, platform engineer, or SRE, take a look. Use what helps. Open issues for what doesn't work. PRs are always welcome.

Infrastructure shouldn't have a paywall.

---

## Post 2: Security-First Infrastructure as Code

**Title:** Security Shouldn't Be an Afterthought in Your Terraform Code

I've audited enough AWS accounts to know: most teams bolt security on after the first incident. GuardDuty gets enabled after a breach. CloudTrail gets configured after an audit finding. Config rules get added after a compliance deadline.

This is backwards.

When I built my open-source Terraform module collection, security-first design was the core principle. Every module ships with secure defaults -- not as optional features, but as the baseline configuration.

Here's what that looks like in practice:

My AWS Security Baseline module (https://github.com/kogunlowo123/terraform-aws-security-baseline) enables GuardDuty, AWS Config, CloudTrail, and IAM Access Analyzer in a single module call. One `terraform apply` and your account has threat detection, compliance monitoring, audit logging, and access analysis. All encrypted with customer-managed KMS keys.

The S3 module (https://github.com/kogunlowo123/terraform-aws-s3-bucket) blocks public access by default and enables server-side encryption. You have to explicitly opt out of security features, not opt in.

The KMS module (https://github.com/kogunlowo123/terraform-aws-kms) configures automatic key rotation and least-privilege key policies out of the box.

On Azure, the Security Center module (https://github.com/kogunlowo123/terraform-azure-security-center) and Key Vault module (https://github.com/kogunlowo123/terraform-azure-key-vault) follow the same philosophy: secure by default, configurable when needed.

The WAF modules for AWS, Azure Front Door, and GCP Cloud Armor all ship with managed rule sets enabled, rate limiting configured, and logging directed to durable storage.

The lesson I've learned: making security the path of least resistance is the only way it actually gets implemented consistently. When the secure option requires more work than the insecure option, teams will always take the shortcut under deadline pressure.

Build security into your defaults. Make insecurity the thing that requires effort.

---

## Post 3: Multi-Cloud Strategy

**Title:** Multi-Cloud Infrastructure: Same Patterns, Different Implementations

"Just make it work on all three clouds" -- the sentence that launches a thousand bad abstractions.

I maintain Terraform modules across AWS, Azure, and GCP. Here's what I've learned about multi-cloud done right.

The biggest mistake teams make is trying to build a universal abstraction layer. A single "create_network" module that works on AWS, Azure, and GCP. It sounds elegant. In practice, it hides critical differences that your team needs to understand.

AWS VPCs have internet gateways and NAT gateways. Azure VNets have NSGs at the subnet level. GCP VPC networks are global with regional subnets. These aren't cosmetic differences -- they fundamentally change how you architect.

My approach: cloud-specific modules with consistent conventions.

All my VPC/VNet modules use the same variable naming patterns. A `cidr_block` is always called `cidr_block`. Tags follow the same structure. Outputs are named consistently. But the internal implementation respects each cloud's resource model.

The networking modules:
- AWS: https://github.com/kogunlowo123/terraform-aws-vpc-complete
- Azure: https://github.com/kogunlowo123/terraform-azure-virtual-network
- GCP: https://github.com/kogunlowo123/terraform-gcp-vpc-network

The Kubernetes modules:
- AWS EKS: https://github.com/kogunlowo123/terraform-aws-eks
- Azure AKS: https://github.com/kogunlowo123/terraform-azure-aks
- GCP GKE: https://github.com/kogunlowo123/terraform-gcp-gke

The real multi-cloud strategy isn't one module to rule them all. It's having well-built, cloud-native modules with enough consistency that your team can move between clouds without relearning everything from scratch.

Respect the cloud. Standardize the interface. Let the implementation be different.

---

## Post 4: MCP Servers and AI-Assisted DevOps

**Title:** I Built 8 MCP Servers for AI-Assisted Infrastructure Management

The way we interact with infrastructure is about to change fundamentally. I've been building tools for this shift, and I want to share what I've learned.

MCP (Model Context Protocol) is a standard for connecting AI assistants to external tools and data sources. Instead of describing your infrastructure to an AI and hoping it understands, MCP lets the AI query your actual environment directly.

I've built and open-sourced 8 MCP servers:

- AWS (https://github.com/kogunlowo123/mcp-server-aws) -- query EC2, S3, Lambda, CloudWatch, and more
- Azure (https://github.com/kogunlowo123/mcp-server-azure) -- inspect Azure resources, read metrics, check configurations
- Kubernetes (https://github.com/kogunlowo123/mcp-server-kubernetes) -- get pod status, read logs, inspect deployments
- Terraform (https://github.com/kogunlowo123/mcp-server-terraform) -- parse state files, understand resource dependencies
- GitHub (https://github.com/kogunlowo123/mcp-server-github) -- read repos, PRs, issues, actions
- DevOps (https://github.com/kogunlowo123/mcp-server-devops) -- CI/CD pipeline context
- Database (https://github.com/kogunlowo123/mcp-server-database) -- schema exploration, query assistance
- Vector DB (https://github.com/kogunlowo123/mcp-server-vector-db) -- RAG pipeline debugging

The practical impact: incident response goes from "let me check 6 dashboards" to "what's wrong with the checkout service?" and getting an answer with full context -- pod status, recent deployments, error logs, and metrics -- in seconds.

This is not about replacing engineers. It's about eliminating the context-switching tax we pay dozens of times per day. The AI handles the data gathering. You handle the decisions.

The full platform is at https://github.com/kogunlowo123/claude-mcp-platform. All open source.

We're still early. But the teams that start building this muscle now will have a significant advantage in 12 months.

---

## Post 5: Open Source Contribution Philosophy

**Title:** Why I Open-Source Everything I Build

I've published 80+ Terraform modules and 8 MCP servers as open-source projects. People sometimes ask why I don't monetize them. Here's my thinking.

Early in my career, I learned infrastructure engineering from open-source modules, blog posts, and community answers. Every best practice I know was shared freely by someone who didn't have to share it. Open-sourcing my work is how I pay that forward.

But it's not just altruism. Building in the open has made me a significantly better engineer.

When you know other people will read your code, you write better code. You add proper documentation. You think about edge cases. You design cleaner interfaces. My private code has never been as good as my public code, and I doubt I'm unique in that.

Open source also creates accountability. When someone opens an issue saying your module doesn't handle a specific edge case, that's free QA from someone with a production use case you didn't consider. Every bug report makes the module better for everyone, including me.

My modules at https://github.com/kogunlowo123 follow a simple philosophy:

1. Secure defaults -- the safe path should be the easy path
2. Production-ready -- examples should be deployable, not toy demonstrations
3. Well-documented -- if it needs a README to be usable, the README needs to be good
4. Consistently structured -- pick up any module and the patterns are familiar

The hardest part of open source isn't writing the code. It's maintaining it. Provider updates, breaking changes, new features, dependency bumps. 80+ modules means constant upkeep. But that maintenance is also what keeps me current with all three major clouds.

If you're considering open-sourcing your infrastructure work: do it. Start with one module. Make it good. The compound returns -- in skill, reputation, and community -- are worth far more than whatever you'd charge for it.

Build in the open. Share what you learn. The infrastructure community is better when we stop solving the same problems in isolation.
