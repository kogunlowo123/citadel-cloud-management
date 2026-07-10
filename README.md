# Citadel Cloud Management — Production Cloud Engineering

> **100+ production-grade guides** for AWS, Azure, GCP, Kubernetes, MCP Servers, DevSecOps, AI/ML & Cloud Careers — all with complete Terraform code.

[![GitHub Actions](https://img.shields.io/github/actions/workflow/status/kogunlowo123/citadel-cloud-management/content-pipeline.yml?label=Content%20Pipeline&style=flat-square)](https://github.com/kogunlowo123/citadel-cloud-management/actions)
[![Articles](https://img.shields.io/badge/Articles-100%2B-brightgreen?style=flat-square)](https://github.com/kogunlowo123/citadel-cloud-management/tree/main/citadel-content/blog)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Stars](https://img.shields.io/github/stars/kogunlowo123/citadel-cloud-management?style=flat-square)](https://github.com/kogunlowo123/citadel-cloud-management/stargazers)

---

## 🏗️ What's Inside

Production-ready cloud infrastructure guides covering **8 content pillars**:

| Pillar | Articles | Topics |
|--------|----------|--------|
| ☁️ **AWS Infrastructure** | 38 | EKS, ECS Fargate, Lambda, RDS Aurora, S3, CloudWatch, Kinesis, Glue, Step Functions, DynamoDB, SQS/SNS, API Gateway, Cognito, GuardDuty, Inspector, Organizations |
| 🔷 **Azure Infrastructure** | 18 | AKS, Container Apps, Cosmos DB, Sentinel, Hub-Spoke, API Management, Event Hubs, Azure ML |
| 🟡 **GCP Infrastructure** | 14 | GKE Autopilot, BigQuery, Cloud Run, Vertex AI, Cloud Armor, Pub/Sub, Spanner, AlloyDB |
| 🤖 **MCP Servers** | 5 | Terraform MCP, Kubernetes MCP, GitHub MCP, AWS MCP, DevOps MCP |
| 🌐 **Multi-Cloud Architecture** | 10 | GitOps/ArgoCD, HashiCorp Vault, Crossplane, Terraform Cloud, Multi-Cloud Cost Optimization |
| 🧠 **AI/ML Engineering** | 7 | AWS Bedrock RAG, SageMaker, Vertex AI Pipelines, AgentForge, Fraud Detector |
| 🔒 **DevSecOps** | 8 | CIS Benchmarks, Container Security, Supply Chain/SBOM, OPA/Rego, Cloud Custodian |
| 🎓 **Career & Certification** | 7 | AWS/Azure/GCP cert roadmaps, Africa cloud careers, Platform Engineering |

---

## 🚀 Featured Articles

### AWS
- [AWS EKS Production Cluster with Terraform](citadel-content/blog/16-aws-eks-production-terraform.md) — IRSA, KMS secrets, Cluster Autoscaler
- [AWS ECS Fargate with Terraform](citadel-content/blog/31-aws-ecs-fargate-terraform.md) — Serverless containers, ALB, auto-scaling
- [AWS Bedrock RAG Pipeline](citadel-content/blog/30-aws-bedrock-rag-terraform.md) — OpenSearch Serverless, Titan Embeddings
- [AWS CloudWatch Observability](citadel-content/blog/32-aws-cloudwatch-observability.md) — Metrics, anomaly detection, composite alarms
- [AWS Step Functions](citadel-content/blog/53-aws-step-functions-terraform.md) — Saga pattern, parallel execution
- [AWS EventBridge](citadel-content/blog/54-aws-eventbridge-terraform.md) — Custom event bus, archive and replay

### Azure
- [Azure Container Apps with Dapr](citadel-content/blog/34-azure-container-apps-terraform.md) — Microservices, KEDA scaling
- [Azure Sentinel SIEM](citadel-content/blog/38-azure-sentinel-siem-terraform.md) — KQL analytics rules, automated playbooks
- [Azure Hub-Spoke Networking](citadel-content/blog/25-azure-hub-spoke-terraform.md) — Azure Firewall Premium, Bastion
- [Azure API Management](citadel-content/blog/62-azure-api-management.md) — Enterprise API gateway, OAuth2

### GCP
- [GCP BigQuery Analytics Platform](citadel-content/blog/35-gcp-bigquery-analytics-terraform.md) — Row-level security, Pub/Sub streaming
- [GCP Cloud Functions Gen2](citadel-content/blog/39-gcp-cloud-functions-gen2.md) — Eventarc, concurrency, VPC connector
- [GCP Cloud Armor WAF](citadel-content/blog/58-gcp-cloud-armor-waf.md) — OWASP CRS, DDoS protection

### MCP Servers
- [Kubernetes MCP Server](citadel-content/blog/37-kubernetes-mcp-server.md) — AI-powered cluster management
- [GitHub MCP Server](citadel-content/blog/48-github-mcp-server.md) — Issues, PRs, repository automation
- [Terraform MCP Server](citadel-content/blog/20-mcp-server-terraform-guide.md) — AI-driven infrastructure deployments

### Career
- [AWS Cloud Career Guide (Africa)](citadel-content/blog/50-aws-cloud-career-guide.md) — $15k → $180k roadmap
- [AI Engineering Career 2026](citadel-content/blog/95-ai-engineering-career-2026.md) — LLM applications
- [Cloud in Africa 2026](citadel-content/blog/100-cloud-africa-2026.md) — Market landscape

---

## 📚 All Articles

Browse all 100 articles in [`citadel-content/blog/`](citadel-content/blog/)

---

## 🛠️ Repository Structure

```
citadel-cloud-management/
├── citadel-content/
│   ├── blog/                    # 100+ production articles (Terraform guides)
│   └── social-media/            # Distribution batch content
├── articles/                    # Long-form deep dives
├── automation/content-engine/   # Growth dashboard + monitor scripts
│   └── GROWTH-DASHBOARD.md      # Live metrics dashboard
└── .github/workflows/           # 4 automated workflows
    ├── content-pipeline.yml     # Daily audit + SEO check
    ├── growth-monitor.yml       # Metrics + email reports
    ├── devto-publish.yml        # Auto-publish to Dev.to
    └── hashnode-publish.yml     # Publish to Hashnode
```

---

## ⚡ Quick Start

Clone and explore locally:

```bash
git clone https://github.com/kogunlowo123/citadel-cloud-management.git
cd citadel-cloud-management
ls citadel-content/blog/
```

Use any article's Terraform code directly:

```bash
# Example: Deploy EKS cluster
cat citadel-content/blog/16-aws-eks-production-terraform.md
```

---

## 📡 Distribution & Follow

| Platform | Link | Status |
|----------|------|--------|
| GitHub | [kogunlowo123/citadel-cloud-management](https://github.com/kogunlowo123/citadel-cloud-management) | ✅ Live — 100 articles |
| Dev.to | Coming soon | 🔄 Auto-publish on push |
| Hashnode | Coming soon | 🔄 Manual dispatch |
| Website | [citadelcloudmanagement.com](https://citadelcloudmanagement.com) | ✅ Live |

---

## 🤝 Contributing

Found a bug in a Terraform snippet? Have a better pattern? 

1. Fork the repo
2. Create a branch: `git checkout -b fix/aws-eks-irsa`
3. Open a PR with your improvement

---

## 📧 Contact

**Citadel Cloud Management**
- Email: citadelcloudmanagement@gmail.com
- GitHub: [@kogunlowo123](https://github.com/kogunlowo123)
- Website: [citadelcloudmanagement.com](https://citadelcloudmanagement.com)

---

*Updated daily by the Growth Monitor at 3:47pm CDT. Last article: #100 — The State of Cloud in Africa 2026.*
