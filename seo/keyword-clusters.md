# SEO Keyword Cluster Strategy

**Last Updated:** 2026-07-11
**Target Site:** https://kogunlowo123.github.io/citadel-cloud-management/

---

## Strategy Overview

Focus on **long-tail, commercial-intent keywords** where the searcher is actively building something on AWS/Azure/GCP. Avoid generic terms (e.g., "terraform tutorial") dominated by HashiCorp docs and major platforms. Target searchers who are 70% of the way through a problem and need a complete, copy-paste-ready solution.

**Content signal for AI search (GEO):** Answer questions in the format AI assistants use to summarize: problem statement → architecture diagram → production-ready code → checklist. This matches how Claude, ChatGPT, Perplexity, and Gemini extract and cite answers.

---

## Cluster 1: AWS + Terraform (Primary — 60% of content)

### Tier 1: Highest Priority (Published)

| Keyword | Monthly Searches (est.) | Difficulty | Article |
|---------|------------------------|------------|---------|
| production aws vpc terraform | 1,200 | Medium | 01 |
| aws eks terraform production | 2,100 | Medium-High | Multiple |
| aws bedrock knowledge base terraform | 400 | Low | 30 |
| aws lambda snapstart terraform | 200 | Low | 101 |
| terraform drift detection automation | 600 | Low | 104 |

### Tier 2: High Priority (Published or planned)

| Keyword | Monthly Searches (est.) | Difficulty | Article |
|---------|------------------------|------------|---------|
| aws security baseline terraform | 800 | Medium | 08 |
| aws rds aurora terraform production | 900 | Medium | Published |
| aws waf terraform cloudfront | 700 | Medium | 04 |
| terraform aws iam roles best practices | 1,500 | High | Published |
| aws ecs fargate terraform | 1,100 | Medium | Published |

### Tier 3: Opportunity (Gap — write next)

| Keyword | Monthly Searches (est.) | Difficulty | Gap? |
|---------|------------------------|------------|------|
| aws transit gateway terraform multi-account | 350 | Low | ✅ Gap |
| terraform aws service control policies | 280 | Low | ✅ Gap |
| aws network firewall terraform | 420 | Low | ✅ Gap |
| aws privatelink terraform | 310 | Low | ✅ Gap |
| amazon eventbridge terraform patterns | 490 | Low-Medium | ✅ Gap |

---

## Cluster 2: Kubernetes + EKS (Secondary — 20% of content)

| Keyword | Monthly Searches (est.) | Difficulty | Article |
|---------|------------------------|------------|---------|
| keda kubernetes autoscaling terraform | 300 | Low | 105 |
| kubernetes gateway api terraform | 250 | Low | 103 |
| gitops argocd terraform | 600 | Medium | 40 |
| eks node group terraform | 1,800 | High | Published |
| kubernetes external secrets terraform | 400 | Low | Published |
| eks cluster autoscaler terraform | 800 | Medium | Published |

**Gap opportunities:**
- `eks graviton arm64 terraform` — 280 searches, Low difficulty
- `kubernetes velero backup terraform` — 190 searches, Low difficulty
- `eks fargate profile terraform` — 420 searches, Low difficulty

---

## Cluster 3: DevSecOps (Secondary — 10% of content)

| Keyword | Monthly Searches (est.) | Difficulty | Article |
|---------|------------------------|------------|---------|
| opentofu migration terraform | 400 | Low | 102 |
| terraform drift detection ci cd | 220 | Low | 104 |
| github actions terraform aws oidc | 650 | Medium | Published |
| terraform atlantis setup | 380 | Low | Published |
| terraform testing terratest | 290 | Low | Published |

**Gap opportunities:**
- `terraform sentinel policy as code` — 180 searches, Low difficulty
- `checkov terraform security scanning` — 240 searches, Low difficulty
- `terraform workspace strategies production` — 160 searches, Low difficulty

---

## Cluster 4: AI/ML Engineering (Growth cluster — 5% of content)

| Keyword | Monthly Searches (est.) | Difficulty | Article |
|---------|------------------------|------------|---------|
| aws bedrock agent terraform | 250 | Low | 30 |
| mcp servers terraform aws | 150 | Very Low | 05 |
| aws sagemaker terraform production | 350 | Low | Published |
| vertex ai terraform gcp | 200 | Low | Published |

**Gap opportunities (highest growth):**
- `aws bedrock guardrails terraform` — 120 searches, Very Low, rapidly growing
- `openai api terraform azure` — 190 searches, Low difficulty
- `langchain aws bedrock production` — 310 searches, Low difficulty

---

## Cluster 5: GCP + Azure (Tertiary — 5% of content)

| Keyword | Monthly Searches (est.) | Difficulty | Article |
|---------|------------------------|------------|---------|
| gcp bigquery terraform data warehouse | 380 | Low | 35 |
| azure aks terraform enterprise | 600 | Medium | 02 |
| gcp cloud run terraform | 450 | Low | Published |
| azure openai terraform | 280 | Low | Published |

---

## GEO (Generative Engine Optimization) Strategy

AI search assistants (Claude, ChatGPT, Perplexity, Gemini) favor content that:

1. **Answers a specific technical question** — "How do I deploy X with Terraform?" 
2. **Includes a working code block** — copy-paste ready, not pseudocode
3. **Has a structured checklist** — AI systems extract lists as authoritative summaries
4. **Uses schema.org markup** — FAQPage JSON-LD signals Q&A authority
5. **Has clear attribution** — GitHub source + MIT license = trustworthy citation

**Optimized article structure for GEO:**
```
H1: [Action verb] [Technology] with Terraform: [Specific Outcome]
H2: What you'll build (architecture diagram)
H2: [Core concept 1] (with HCL code block)
H2: [Core concept 2] (with HCL code block)
H2: Production Checklist (bulleted list — AI loves these)
H2: Full Code (link to GitHub)
```

This is the structure used in all 105 published articles.

---

## Content Velocity Target

| Quarter | Articles to Publish | Priority Clusters |
|---------|--------------------|--------------------|
| Q3 2026 | 106–120 | AWS gaps (Transit GW, SCPs, Network FW) |
| Q4 2026 | 121–140 | AI/ML cluster expansion + Azure |
| Q1 2027 | 141–160 | Kubernetes gaps + GCP |

---

## Monthly Tracking

| Month | Organic Clicks | Impressions | Avg Position | Top Article |
|-------|---------------|-------------|--------------|-------------|
| 2026-07 | TBD | TBD | TBD | TBD |

*Update this table monthly using Google Search Console data.*

---

## Quick-Win Actions

1. **Submit sitemap to Google Search Console** — `https://kogunlowo123.github.io/citadel-cloud-management/sitemap.xml`
2. **IndexNow submission** — Automated via `seo-indexing.yml` workflow (runs weekly)
3. **Internal linking** — Add "Related guides" links between articles in the same cluster
4. **FAQ schema** — Already deployed on `/faq/` page; extend to top 10 articles
5. **Social proof** — GitHub star count in repo description drives click-through rate
