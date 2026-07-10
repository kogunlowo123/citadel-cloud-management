# AWS Cloud Career Guide: From Junior to Solutions Architect

**Pillar:** Career & Certification
**SEO Target:** aws cloud career guide solutions architect africa certification roadmap
**Word Count:** ~1500

Cloud architecture is the fastest path to a $100k+ salary in tech. AWS, Azure, and GCP are hiring globally — and the African market specifically needs cloud professionals who understand both global standards and local constraints. This guide maps your path from beginner to Solutions Architect with certifications, projects, and salary benchmarks.

## The Cloud Career Ladder

| Level | Role | Salary (Africa/Remote) | Key Skills |
|-------|------|------------------------|------------|
| Entry | Cloud Support Eng | $15k–$25k / R200k–R400k | Console, basic networking, S3, EC2 |
| Mid | Cloud Engineer | $30k–$60k / R400k–R800k | IaC, Terraform, EKS, CI/CD |
| Senior | Senior Cloud Eng | $60k–$100k / R800k–R1.4M | Architecture, multi-cloud, security |
| Staff | Solutions Architect | $100k–$180k / R1.4M+ | System design, cost optimization, sales |
| Principal | Cloud Architect | $150k–$250k+ | Platform strategy, FinOps, org-wide |

## Certification Roadmap: 12 Months to Solutions Architect

### Month 1–2: Foundation
**AWS Cloud Practitioner (CLF-C02)**
- Study: Andrew Brown's free YouTube course (12h)
- Cost: $100 (free vouchers via AWS Educate)
- Pass score: 70%
- Key topics: billing, global infrastructure, basic services

### Month 3–4: Associate Level
**AWS Solutions Architect Associate (SAA-C03)**
- Study: Adrian Cantrill's course (100h) — best on the market
- Practice exams: Tutorials Dojo (6 sets, 390 questions)
- Cost: $150 exam + $60 course
- Key domains: design resilient architectures, cost optimization, security

### Month 5–6: Terraform Skills
**HashiCorp Terraform Associate (003)**
- Study: official tutorials + Andrew Brown YouTube
- Build: deploy 3 real projects (EKS cluster, Aurora, ECS Fargate)
- GitHub portfolio: 5+ Terraform modules with README and architecture diagrams
- Cost: $70

### Month 7–9: Professional Level
**AWS Solutions Architect Professional (SAP-C02)**
- Study: Adrian Cantrill SAP course (150h)
- This exam tests real architecture decisions, not just service names
- Cost: $300 — worth it for the salary premium (+$20k–$40k)

### Month 10–12: Specialization
Choose one based on target role:
- **Security Specialty (SCS-C02)** → CISO-adjacent, highest demand in fintech/banking
- **Data Analytics Specialty (DAS-C01)** → Data engineering + ML ops
- **DevOps Professional (DOP-C02)** → Platform engineering teams

## Building Your Portfolio

### Project 1: Three-Tier Web App (Month 1-2)
```hcl
# Start with this pattern
module "three_tier" {
  source = "github.com/your-org/terraform-aws-three-tier"
  
  vpc_cidr        = "10.0.0.0/16"
  web_instance_type = "t3.small"
  db_instance_class = "db.t3.micro"
}
```
Write up: "I deployed a scalable web application on AWS with VPC, ALB, EC2 Auto Scaling, and RDS. Here's the architecture diagram and Terraform code."

### Project 2: Serverless API (Month 3-4)
- Lambda + API Gateway + DynamoDB + Cognito
- 100% Terraform, GitHub Actions CI/CD
- Real-world: build a simple expense tracker API

### Project 3: EKS Microservices (Month 5-6)
- EKS with IRSA, ECR, ALB Ingress Controller
- Helm charts + ArgoCD GitOps
- Observability: CloudWatch Container Insights + Prometheus

## Job Search Strategy for Africa

### Remote First (Highest Leverage)
1. **LinkedIn**: Add "Open to Remote" + "AWS" + "Terraform" to headline
2. **Toptal**: Rigorous screening but 3-5× local rates
3. **Turing**: Good for SA/Nigeria/Kenya engineers
4. **Arc.dev**: Growing remote marketplace

### Local Market (SA, Nigeria, Kenya)
- **South Africa**: Standard Bank, FNB, Investec, MTN all hiring cloud engineers
- **Nigeria**: Flutterwave, Interswitch, Access Bank — AWS/GCP heavy
- **Kenya**: Safaricom, NCBA, M-Pesa infrastructure — hybrid cloud

### Salary Negotiation
1. Never give a number first — "What's the budget for this role?"
2. Lead with market data: ZAR R650k–R900k for Senior in SA (2026)
3. Always negotiate benefits: training budget ($5k/year), home office allowance, remote-first

## Free Resources

| Resource | What | URL |
|----------|------|-----|
| AWS Skill Builder | Official training, 500+ free courses | skillbuilder.aws |
| Andrew Brown | Full cert courses on YouTube (free) | freecodecamp.org |
| A Cloud Guru | First 7 days free, then $35/month | acloudguru.com |
| Tutorials Dojo | Best practice exams | tutorialsdojo.com |
| AWS Educate | Free AWS credits + training for students | aws.amazon.com/educate |
| GitHub Student Pack | Free Terraform Cloud, GitHub Actions, and more | education.github.com |

## 30-Day Action Plan

1. **Day 1**: Create AWS free tier account, set billing alerts at $5
2. **Day 2-7**: Complete AWS Cloud Practitioner Essentials on Skill Builder (free)
3. **Day 8-14**: Deploy your first VPC with public/private subnets using Terraform
4. **Day 15-21**: Build three-tier app project, push to GitHub with README
5. **Day 22-30**: Register for SAA-C03 exam, start Adrian Cantrill course

The cloud career path is one of the clearest ROI journeys in African tech: $100 in cert fees → $30k+ salary premium within 12 months of consistent study and building.

## About This Guide

This guide is part of the Citadel Cloud Management content series covering AWS, Azure, GCP, DevSecOps, MCP Servers, and Cloud Careers. Follow our GitHub: https://github.com/kogunlowo123/citadel-cloud-management
