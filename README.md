# Citadel Cloud Management

> Content engine, growth automation, SEO pipeline, and monitoring infrastructure for [citadelcloudmanagement.com](https://www.citadelcloudmanagement.com)

[![Content Pipeline](https://github.com/kogunlowo123/citadel-cloud-management/actions/workflows/content-pipeline.yml/badge.svg)](https://github.com/kogunlowo123/citadel-cloud-management/actions/workflows/content-pipeline.yml)
[![Growth Monitor](https://github.com/kogunlowo123/citadel-cloud-management/actions/workflows/growth-monitor.yml/badge.svg)](https://github.com/kogunlowo123/citadel-cloud-management/actions/workflows/growth-monitor.yml)

---

## What This Repo Contains

| Directory | Contents |
|-----------|----------|
| `citadel-content/blog/` | Article pipeline — production-ready blog posts (target: 100+) |
| `citadel-content/social-media/` | Weekly distribution batches for Twitter, LinkedIn, Reddit |
| `articles/` | Original long-form articles |
| `devto-ready/` | Platform-formatted articles for Dev.to |
| `automation/content-engine/` | Growth dashboard and monitoring scripts |
| `.github/workflows/` | CI/CD: content pipeline, daily growth monitor |
| `social/` | Raw social media content |
| `scripts/` | Automation and helper scripts |
| `seo/` | SEO metadata, sitemap config, schema markup |

## Quick Metrics

| Metric | Status |
|--------|--------|
| Blog articles | See [GROWTH-DASHBOARD.md](automation/content-engine/GROWTH-DASHBOARD.md) |
| Content pillars covered | 8 (AWS, Azure, GCP, MCP, Multi-Cloud, AI/ML, DevSecOps, Career) |
| GitHub org repos | [83 repos](https://github.com/Citadel-Cloud-Management) |
| Website | [citadelcloudmanagement.com](https://www.citadelcloudmanagement.com) |

## Content Pillars

1. **AWS Infrastructure** — VPC, EKS, ECS, RDS, Lambda, WAF, Security Baseline
2. **Azure Infrastructure** — AKS, Key Vault, OpenAI, Hub-Spoke, Sentinel
3. **GCP Infrastructure** — GKE Autopilot, Vertex AI, Cloud Run, BigQuery
4. **MCP Servers** — Terraform, AWS, Azure, K8s, GitHub, Database, DevOps, Vector DB
5. **Multi-Cloud Architecture** — Landing zones, governance, cross-cloud networking
6. **AI/ML Engineering** — Bedrock, AgentForge, RAG pipelines, multi-agent systems
7. **DevSecOps** — Security baseline, WAF, GuardDuty, compliance-as-code
8. **Career & Certification** — Cloud career guide for Africa, AWS cert study guide

## Daily Monitor

A scheduled Claude Code routine runs at **3:47pm CDT daily** and:

- Checks website SEO health (sitemap, meta tags, JSON-LD)
- Counts articles and social distribution pieces
- Updates `automation/content-engine/GROWTH-DASHBOARD.md`
- Sends email report via Resend API
- Writes a new article if count < 100

### Required Setup for the Monitor

1. **Network policy** — Add `citadelcloudmanagement.com` and `api.resend.com` to allowlist at [claude.ai/code/environments](https://claude.ai/code/environments)
2. **Resend API key** — Add `RESEND_API_KEY` as a GitHub Actions secret (Settings → Secrets → Actions)
3. **GitHub Actions** — Already configured in `.github/workflows/growth-monitor.yml`

## GitHub Actions Setup

Add these secrets in **Settings → Secrets and variables → Actions**:

| Secret | Value | Required for |
|--------|-------|-------------|
| `RESEND_API_KEY` | `re_VyxRSaxf_...` | Email reports |

## Links

- **Website:** [citadelcloudmanagement.com](https://www.citadelcloudmanagement.com)
- **GitHub Org:** [github.com/Citadel-Cloud-Management](https://github.com/Citadel-Cloud-Management)
- **Personal Repos:** [github.com/kogunlowo123](https://github.com/kogunlowo123)
- **Growth Dashboard:** [GROWTH-DASHBOARD.md](automation/content-engine/GROWTH-DASHBOARD.md)
