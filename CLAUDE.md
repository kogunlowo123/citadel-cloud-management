# Citadel Cloud Management — Claude Code Configuration

## Project Overview

This is the Citadel Cloud Management content engine and growth automation repository.
Website: https://www.citadelcloudmanagement.com
GitHub org: https://github.com/Citadel-Cloud-Management
Personal repos: https://github.com/kogunlowo123

## Repository Structure

```
citadel-cloud-management/
├── automation/content-engine/   # Monitoring scripts and dashboard
│   ├── GROWTH-DASHBOARD.md      # Daily metrics (updated by monitor)
│   └── monitor.sh               # Monitoring helper scripts
├── citadel-content/
│   ├── blog/                    # Article pipeline (target: 100+ articles)
│   └── social-media/            # Distribution batches
├── articles/                    # Original long-form articles
├── devto-ready/                 # Platform-ready formatted articles
├── seo/                         # SEO metadata and sitemap config
├── scripts/                     # Automation scripts
├── social/                      # Social media content
├── .claude/settings.json        # Claude Code hooks
└── .github/workflows/           # CI/CD pipelines
```

## Daily Growth Monitor

The scheduled monitor runs at 3:47pm CDT (America/Chicago) and performs:

1. **SEO Health Check** — WebFetch sitemap.xml, blogs/news page, homepage
2. **Content Velocity** — Count files in citadel-content/blog/ and social-media/
3. **Growth Metrics Update** — Write to automation/content-engine/GROWTH-DASHBOARD.md
4. **Issue Detection** — Broken pages, stale content, pillar gaps
5. **Daily Email Report** — Send via Resend API to citadelcloudmanagement@gmail.com
6. **Compound Actions** — Write new article if count < 100

## CRITICAL: Network Policy Requirements

The monitoring routine REQUIRES these domains to be whitelisted in the Claude Code
session's egress policy. Without them, SEO checks and email reports fail.

**Required domains:**
- `www.citadelcloudmanagement.com` — SEO health checks
- `citadelcloudmanagement.com` — Website access
- `api.resend.com` — Email delivery (Resend API)

**How to fix:**
1. Go to https://claude.ai/code/environments
2. Select your monitoring environment
3. Under "Network Access", set level to "Internet" or add the domains above to the allowlist
4. Re-run the monitoring session

See: https://code.claude.com/docs/en/claude-code-on-the-web#network-access

## Resend API

Email reports use Resend. Key: stored in environment variable RESEND_API_KEY.
From: Citadel Growth Monitor <onboarding@resend.dev>
To: citadelcloudmanagement@gmail.com

To add the key: set RESEND_API_KEY=re_VyxRSaxf_2jiSHxnoSN4cpcMxhz3EYEhp in your
Claude Code environment settings at https://claude.ai/code/environments

## Content Targets

| Metric | Target | Current |
|--------|--------|---------|
| Blog articles | 100+ | See GROWTH-DASHBOARD.md |
| Social batches | Weekly | See GROWTH-DASHBOARD.md |
| Sitemap URLs | 50+ | See GROWTH-DASHBOARD.md |
| Pillar coverage | All 8 pillars | See GROWTH-DASHBOARD.md |

## Content Pillars

1. AWS Infrastructure (Terraform modules, EKS, VPC, RDS)
2. Azure Infrastructure (AKS, Key Vault, OpenAI, Hub-Spoke)
3. GCP Infrastructure (GKE, Vertex AI, Cloud Run)
4. MCP Servers (Terraform, AWS, Azure, K8s, GitHub)
5. Multi-Cloud Architecture (Landing zones, governance)
6. AI/ML Engineering (Bedrock, Vertex AI, AgentForge)
7. DevSecOps (Security baseline, WAF, GuardDuty)
8. Career & Certification (Cloud career, AWS cert guide)

## Compound Article Writing

When the monitor finds article count < 100, it should write a 1,500+ word article on
the highest-priority pillar gap. Save to citadel-content/blog/ and commit/push.

## Timezone

All scheduled operations: America/Chicago (CDT)
