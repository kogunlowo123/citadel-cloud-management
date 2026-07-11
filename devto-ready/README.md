# Dev.to Ready Articles

Platform-formatted versions of Citadel Cloud Management guides for Dev.to cross-posting.

Each file contains YAML frontmatter with:
- `published: true` — ready to POST via Dev.to API
- `canonical_url` — points back to the full GitHub guide (SEO credit stays on source)
- `series` — groups all articles under "Citadel Cloud Management: 100 Free Terraform Guides"
- `tags` — up to 4 Dev.to tags

## Articles Ready for Publishing

| File | Article | Tags |
|------|---------|------|
| `01-production-vpc-terraform-devto.md` | Production AWS VPC | aws, terraform, devops, networking |
| `08-aws-security-baseline-devto.md` | AWS Security Baseline | aws, terraform, security, devops |
| `30-aws-bedrock-rag-terraform-devto.md` | Bedrock RAG Pipeline | aws, terraform, ai, devops |
| `35-gcp-bigquery-analytics-terraform-devto.md` | GCP BigQuery Platform | gcp, terraform, dataengineering, analytics |
| `40-gitops-argocd-terraform-devto.md` | GitOps with ArgoCD | kubernetes, terraform, gitops, devops |

## Publishing via API

The `global-distribution.yml` workflow handles weekly auto-publishing.
To publish manually via Dev.to API:

```bash
curl -X POST https://dev.to/api/articles \
  -H "api-key: $DEV_TO_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"article\": {\"body_markdown\": $(cat 01-production-vpc-terraform-devto.md | jq -Rs .)}}"
```

## Priority Order

1. `01-production-vpc-terraform-devto.md` — highest search volume (production aws vpc terraform)
2. `08-aws-security-baseline-devto.md` — high commercial intent (aws security baseline terraform)
3. `40-gitops-argocd-terraform-devto.md` — trending topic (gitops argocd terraform)
4. `30-aws-bedrock-rag-terraform-devto.md` — AI/ML traffic (bedrock rag terraform)
5. `35-gcp-bigquery-analytics-terraform-devto.md` — GCP audience
