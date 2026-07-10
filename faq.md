---
layout: page
title: "FAQ — Citadel Cloud Management Terraform Guides"
description: "Frequently asked questions about the free Terraform guides for AWS, Azure, GCP, Kubernetes, and DevSecOps."
permalink: /faq/
---

# Frequently Asked Questions

## General

**Are all the guides really free?**
Yes. Every guide is MIT licensed, open source, and free to use commercially. No paywall, no email required.

**How many guides are available?**
100+ production-ready Terraform guides covering AWS (35+), Azure (15+), GCP (13+), MCP Servers (8+), DevSecOps (9+), AI/ML Engineering (8+), Multi-Cloud Architecture (10+), and Cloud Careers (9+).

**What Terraform version do the guides target?**
All guides use Terraform >= 1.5 with the latest stable provider versions. Provider version pins are specified in each guide.

**Can I use these in a commercial project?**
Yes. MIT license — use, copy, modify, and distribute freely including in commercial projects.

---

## AWS Terraform Guides

**What AWS services are covered?**
VPC, EKS (with Karpenter), ECS Fargate, Lambda, RDS Multi-AZ, Bedrock Knowledge Bases, SageMaker, GuardDuty, Security Hub, Inspector v2, WAF v2, CloudFront, EventBridge, Step Functions, DynamoDB, ElastiCache, Kinesis, Glue, Athena, Cost Anomaly Detection, Control Tower, AWS Organizations, SSM Parameter Store, Route53, Transfer Family, DataSync, FSx Lustre, AppSync, Cognito, API Gateway, S3 advanced patterns.

**Is there an EKS Terraform module with Karpenter?**
Yes — [guide 01](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/01-production-vpc-terraform.md) covers production VPC, and the EKS + Karpenter guide covers Bottlerocket AMI, Spot/On-Demand node pools, and IRSA.

---

## Azure Terraform Guides

**What Azure services are covered?**
AKS with CNI, Container Apps with Dapr, Key Vault (including HSM), Cosmos DB, Azure API Management, Sentinel SIEM, Azure Arc, Azure Landing Zone, Azure DevOps pipelines, Application Gateway, Event Hubs, AlloyDB equivalent (Azure SQL Hyperscale), Workload Identity, Azure ML, OpenAI Service.

---

## GCP Terraform Guides

**What GCP services are covered?**
GKE Autopilot with Workload Identity, BigQuery with dbt, Vertex AI, Cloud Armor, Spanner, AlloyDB, Cloud Functions Gen2, Pub/Sub, Cloud Run, GCP Landing Zone, GCP cost optimization, GCP certifications guide.

---

## MCP Servers

**What MCP server guides are available?**
Terraform MCP Server, AWS MCP Server, Kubernetes MCP Server, GitHub MCP Server, and a complete DevOps MCP guide covering how to connect Claude to your cloud infrastructure.

---

## DevSecOps

**Which security frameworks are covered?**
CIS Benchmarks implementation, AWS WAF v2, GuardDuty + Security Hub, Inspector v2, OPA/Rego policy testing for Terraform, supply chain security (SBOM, Sigstore, Cosign, Falco), HashiCorp Vault + AWS Secrets Manager integration, and CI/CD security hardening.

---

## AI/ML Engineering

**Is there a Bedrock RAG pipeline guide?**
Yes — [AWS Bedrock Knowledge Base with Terraform](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/30-aws-bedrock-rag-terraform.md) covers OpenSearch Serverless, Titan Embeddings v2, hierarchical chunking, and Bedrock Agent with Claude 3.5 Sonnet.

---

## Contributing

**Can I submit a guide?**
Yes! Fork the repo, write your guide in the `citadel-content/blog/` format, and open a pull request. See [CONTRIBUTING.md](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/CONTRIBUTING.md).

**I found an error. How do I report it?**
Open an [issue on GitHub](https://github.com/kogunlowo123/citadel-cloud-management/issues) describing the problem and the guide file name.

---

## Contact

Email: [citadelcloudmanagement@gmail.com](mailto:citadelcloudmanagement@gmail.com)
Website: [citadelcloudmanagement.com](https://www.citadelcloudmanagement.com)
GitHub: [kogunlowo123/citadel-cloud-management](https://github.com/kogunlowo123/citadel-cloud-management)
