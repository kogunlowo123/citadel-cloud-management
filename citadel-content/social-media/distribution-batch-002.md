# Distribution Batch 002 — 100-Article Milestone Push

**Date:** 2026-07-10
**Status:** Ready to post
**Goal:** Announce 100-article milestone across all channels

---

## LinkedIn — Post 1 (Milestone Announcement)

**Post immediately. Best time: Tuesday–Thursday 9am–11am local.**

---

We just published our 100th free cloud engineering article.

100 production-ready Terraform guides for AWS, Azure, and GCP.
No paywall. No signup. MIT licensed.

Here's what's in the library:

→ AWS: EKS, ECS Fargate, Lambda, RDS, Bedrock RAG, SageMaker, GuardDuty, Inspector, Control Tower, Cost Anomaly Detection

→ Azure: AKS, Container Apps (Dapr), Key Vault HSM, Cosmos DB, API Management, Sentinel, Azure Arc

→ GCP: GKE, BigQuery, Vertex AI, Cloud Armor, Spanner, AlloyDB, Cloud Functions Gen2

→ MCP Servers: Terraform MCP, AWS MCP, Kubernetes MCP, GitHub MCP

→ DevSecOps: WAF, OPA/Rego, supply chain security, SBOM, Falco, Cosign

→ AI/ML: Bedrock Knowledge Bases, SageMaker pipelines, Vertex AI, AgentForge

→ FinOps: Cost anomaly detection, Azure cost management, GCP cost optimization

→ Multi-cloud: Landing zones, Crossplane, Anthos, AWS Organizations

Every article has:
✅ Copy-paste Terraform code
✅ Production IAM policies
✅ Security controls
✅ Production checklist

This is free forever. Built for cloud engineers at all levels — from career starters to senior architects.

GitHub: https://github.com/kogunlowo123/citadel-cloud-management

Tag a cloud engineer who needs this. 👇

#Terraform #AWS #Azure #GCP #CloudEngineering #DevOps #Kubernetes #Infrastructure

---

## LinkedIn — Post 2 (Technical Deep Dive — 3 days after Post 1)

---

Most AWS Bedrock RAG guides stop at "call the API."

Here's what a production Bedrock Knowledge Base actually needs:

🔐 OpenSearch Serverless with:
  - Encryption policy (AWS-owned KMS)
  - Network policy (VPC endpoint, no public access)
  - Data access policy (scoped to Bedrock role + caller)

📦 Knowledge Base with:
  - Titan Embeddings v2 (1536-dim vectors)
  - Hierarchical chunking: 1500 parent / 300 child tokens
  - S3 trigger for automatic ingestion on document upload

🤖 Bedrock Agent:
  - Claude 3.5 Sonnet as foundation model
  - SourceArn condition on IAM role (prevents confused deputy attack)
  - 600s idle session TTL

All of this is in the free Terraform guide:
https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/30-aws-bedrock-rag-terraform.md

The full library has 100 guides like this.
No paywall. MIT licensed.

#AWS #Bedrock #RAG #Terraform #AIEngineering #LLM #CloudSecurity

---

## LinkedIn — Post 3 (Career/Community — 5 days after Post 1)

---

To every engineer in Africa building cloud skills:

The path to a cloud engineering career doesn't require $500 bootcamps or expensive courses.

Here's what actually works:

1. Get AWS CCP (free resources, ~$100 exam)
2. Build one real project in public (GitHub)
3. Write about what you learned (Dev.to, LinkedIn)
4. Contribute to open source cloud projects
5. Join cloud communities (AWS Community Builders, CNCF)

I wrote the complete guide here (free):
https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/98-cloud-engineering-career-africa.md

And the AWS certification roadmap for 2026:
https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/22-aws-certification-roadmap.md

The full library (100 free guides) is at:
https://github.com/kogunlowo123/citadel-cloud-management

You have everything you need.

#CloudEngineering #AWSCertification #AfricaTech #TechCareer #DevOps

---

## Twitter / X — Thread 1 (Milestone)

**Tweet 1 (hook):**
I just published my 100th free cloud engineering article.

100 production Terraform guides for AWS, Azure, and GCP.

Here's what's in the library 🧵

**Tweet 2:**
AWS coverage (35+ guides):
- EKS + Karpenter
- ECS Fargate (blue/green)
- Lambda@Edge
- RDS Multi-AZ
- Bedrock RAG pipeline
- SageMaker training
- GuardDuty + Security Hub
- Control Tower
- Cost Anomaly Detection

**Tweet 3:**
Azure coverage (15+ guides):
- AKS + CNI
- Container Apps + Dapr
- Key Vault HSM
- Cosmos DB + Synapse Link
- API Management
- Azure Sentinel
- Azure Arc
- Azure Landing Zone

**Tweet 4:**
GCP coverage (12+ guides):
- GKE Autopilot
- BigQuery + dbt
- Vertex AI
- Cloud Armor
- Spanner
- AlloyDB
- Cloud Functions Gen2
- GCP Landing Zone

**Tweet 5:**
Plus:
- 8 MCP server guides (Terraform MCP, AWS MCP, K8s MCP)
- DevSecOps: WAF, OPA/Rego, SBOM, Falco
- AI/ML: Bedrock, SageMaker, Vertex AI, AgentForge
- FinOps: cost anomaly, cloud cost optimization
- Multi-cloud: Crossplane, Anthos, AWS Organizations

**Tweet 6:**
Every guide includes:
✅ Full Terraform code (copy-paste)
✅ IAM policies
✅ Security controls
✅ Production checklist

All free. MIT licensed. No paywall.

GitHub: https://github.com/kogunlowo123/citadel-cloud-management

RT if this helps someone in your network 🙏

---

## Twitter / X — Standalone Tweets (post 1/day)

**Tweet A:**
Free: AWS Bedrock RAG pipeline with Terraform

Includes:
- OpenSearch Serverless with VPC endpoint
- Titan Embeddings v2
- Hierarchical chunking (1500/300 tokens)
- Bedrock Agent (Claude 3.5 Sonnet)
- S3 trigger for auto-ingestion

https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/30-aws-bedrock-rag-terraform.md

#AWS #Bedrock #RAG #Terraform

---

**Tweet B:**
EKS with Karpenter + Bottlerocket on Terraform

Most guides skip the production details.

This one includes:
- Bottlerocket optimized AMI
- Spot + On-Demand mixed node pools
- Karpenter NodePool with disruption budget
- IRSA for pod-level AWS permissions

Free: https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/01-eks-karpenter-bottlerocket-terraform.md

#EKS #Kubernetes #Terraform #AWS

---

**Tweet C:**
Free OPA/Rego policy testing for Terraform

Stop finding security misconfigurations after deploy.

This guide shows:
- Write Rego policies for Terraform plans
- Test with conftest in CI
- Block S3 buckets without encryption
- Enforce tagging requirements
- Deny public EKS API endpoints

https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/71-opa-rego-policy-terraform.md

#DevSecOps #OPA #Terraform #Kubernetes

---

## Reddit Posts (copy-paste — see distribution guide in Gmail drafts)

See Gmail draft: "REDDIT DISTRIBUTION GUIDE" for r/devops, r/aws, r/Terraform, r/kubernetes

**Timing:**
- Post 1: r/devops — Monday
- Post 2: r/aws — Wednesday  
- Post 3: r/Terraform — Friday
- Post 4: r/kubernetes — following Monday

---

## Dev.to Article Queue (publish via GitHub Actions when DEV_TO_API_KEY is set)

Priority order for cross-posting:
1. `30-aws-bedrock-rag-terraform.md` — high search volume
2. `01-eks-karpenter-bottlerocket-terraform.md` — evergreen
3. `21-aws-security-baseline-terraform.md` — security content does well
4. `36-gcp-bigquery-terraform.md` — trending topic
5. `41-argocd-gitops-terraform.md` — high community interest

To activate: Add `DEV_TO_API_KEY` secret at https://github.com/kogunlowo123/citadel-cloud-management/settings/secrets/actions

---

## Newsletter Submission Status

| Newsletter | Draft in Gmail | Status |
|------------|---------------|--------|
| Last Week in AWS | ✅ Draft created | Send manually |
| cloudonaut.io | ✅ Draft created | Send manually |
| TLDR DevOps | ✅ Draft created | Send manually |
| AWS Weekly | ✅ Draft created | Send manually |
| Dev.to partnership | ✅ Draft created | Send manually |

---

## GitHub Discussions Seeded

| Discussion | URL | Category |
|------------|-----|----------|
| 100-article milestone | https://github.com/kogunlowo123/citadel-cloud-management/discussions/2 | Announcements |
| Quick-start by role | https://github.com/kogunlowo123/citadel-cloud-management/discussions/3 | Q&A |
| Vote for next guides | https://github.com/kogunlowo123/citadel-cloud-management/discussions/4 | Ideas |
| Show and tell | https://github.com/kogunlowo123/citadel-cloud-management/discussions/5 | Show and tell |
