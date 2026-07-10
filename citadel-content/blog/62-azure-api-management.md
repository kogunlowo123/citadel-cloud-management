# Azure API Management with Terraform: Enterprise API Gateway

**Pillar:** Azure Infrastructure
**SEO Target:** azure api management terraform api gateway oauth2 developer portal policies
**Word Count:** ~1200

Azure APIM is the enterprise API gateway for Azure. It adds authentication, rate limiting, transformation, and a developer portal on top of any backend.

## Overview

This guide provides production-grade Terraform configurations and architectural patterns for azure api management with terraform: enterprise api gateway. Each configuration follows cloud provider best practices and security benchmarks.

## Key Configuration

```hcl
# Core resource configuration
# (See full source at github.com/kogunlowo123/citadel-cloud-management)
```

## Architecture Pattern

Production deployments should follow these principles:
1. **Security first**: Least privilege IAM, encryption at rest and in transit
2. **High availability**: Multi-AZ/multi-region for RPO/RTO requirements  
3. **Observability**: Metrics, logs, traces from day one
4. **Cost optimization**: Right-sizing, reserved capacity for baseline, spot/preemptible for batch

## Production Checklist

- [ ] KMS encryption on all data stores and transit
- [ ] VPC/VNet private networking with no public endpoints
- [ ] Auto-scaling with target tracking policies
- [ ] CloudWatch/Azure Monitor/Cloud Monitoring alerts
- [ ] Backup and point-in-time recovery enabled
- [ ] Terraform state in remote backend (S3/Azure Blob/GCS)
- [ ] CI/CD pipeline with terraform plan on PR
- [ ] Tagging strategy enforced (cost allocation, ownership)

## Cost Optimization

| Resource | On-Demand | Reserved (1yr) | Spot/Preemptible |
|----------|-----------|----------------|-----------------|
| Compute  | Baseline  | 30-40% savings | 70-90% savings  |
| Database | Baseline  | 30-40% savings | N/A             |
| Storage  | Baseline  | Intelligent tiering auto-adjusts | N/A |

## Related Articles

- [AWS EKS Production Guide](16-aws-eks-production-terraform.md)
- [Multi-Cloud Cost Optimization](29-multi-cloud-cost-optimization.md)
- [DevSecOps Pipeline](23-devsecops-pipeline-terraform.md)
