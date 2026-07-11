---
title: "AWS Bedrock Knowledge Base with Terraform: RAG Pipeline in Production"
published: true
description: "Deploy a production Bedrock RAG pipeline with Terraform: OpenSearch Serverless, Titan Embeddings v2, hierarchical chunking, and Bedrock Agent. Full Terraform code included."
tags: aws, terraform, ai, devops
series: "Citadel Cloud Management: 100 Free Terraform Guides"
canonical_url: https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/30-aws-bedrock-rag-terraform.md
cover_image: https://kogunlowo123.github.io/citadel-cloud-management/assets/images/og-default.png
---

> **This is part of the [Citadel Cloud Management](https://github.com/kogunlowo123/citadel-cloud-management) free Terraform guide library — 100+ production-ready guides, MIT licensed, no paywall.**

AWS Bedrock Knowledge Bases provides managed Retrieval-Augmented Generation (RAG). You connect a data source (S3, Confluence, SharePoint), Bedrock handles chunking, embedding, and vector storage, and your agents retrieve relevant context automatically.

## What you'll build

```
S3 Data Source (PDFs, docs, HTML)
        ↓
Bedrock Knowledge Base
   ├── Titan Embeddings v2 (1536-dim vectors)
   └── OpenSearch Serverless (VPC endpoint, no public access)
        ↓
Bedrock Agent (Claude 3.5 Sonnet)
        ↓
Your Application
```

## OpenSearch Serverless Collection

```hcl
resource "aws_opensearchserverless_collection" "kb" {
  name             = "${var.prefix}-kb-collection"
  type             = "VECTORSEARCH"
  standby_replicas = var.environment == "prod" ? "ENABLED" : "DISABLED"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.main
  ]

  tags = var.tags
}
```

Security policies (encryption + network with VPC endpoint) are required before the collection is created. Full code in the [original guide](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/30-aws-bedrock-rag-terraform.md).

## Knowledge Base with Hierarchical Chunking

```hcl
resource "aws_bedrockagent_knowledge_base" "main" {
  name     = "${var.prefix}-knowledge-base"
  role_arn = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = opensearch_index.kb.name
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }
}

resource "aws_bedrockagent_data_source" "s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  name              = "${var.prefix}-s3-docs"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = aws_s3_bucket.kb_data.arn
      inclusion_prefixes = ["documents/", "faqs/"]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "HIERARCHICAL"
      hierarchical_chunking_configuration {
        level_configurations { max_tokens = 1500 }  # Parent chunk
        level_configurations { max_tokens = 300 }   # Child chunk (retrieved)
        overlap_tokens = 60
      }
    }
  }
}
```

## Bedrock Agent

```hcl
resource "aws_bedrockagent_agent" "main" {
  agent_name              = "${var.prefix}-agent"
  agent_resource_role_arn = aws_iam_role.bedrock_agent.arn
  foundation_model        = "anthropic.claude-3-5-sonnet-20241022-v2:0"
  idle_session_ttl_in_seconds = 600
  instruction = var.agent_instruction
}

resource "aws_bedrockagent_agent_knowledge_base_association" "main" {
  agent_id             = aws_bedrockagent_agent.main.agent_id
  knowledge_base_id    = aws_bedrockagent_knowledge_base.main.id
  knowledge_base_state = "ENABLED"
}
```

## Production Checklist

- [ ] OpenSearch Serverless with VPC endpoint (no public access)
- [ ] Bedrock role with `SourceArn` condition (prevents confused deputy attack)
- [ ] Hierarchical chunking: 1500 parent / 300 child tokens
- [ ] S3 trigger for automatic ingestion on new document upload
- [ ] STANDBY_REPLICAS enabled for production collections
- [ ] CloudWatch logging on all Lambda functions

## Full code

The complete guide with all IAM policies, OpenSearch index configuration, ingestion Lambda, and S3 trigger is at:

👉 [github.com/kogunlowo123/citadel-cloud-management — Article 30](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/30-aws-bedrock-rag-terraform.md)

---

*Part of 100 free production Terraform guides covering AWS, Azure, GCP, Kubernetes, DevSecOps, AI/ML, and Cloud Careers. MIT licensed. [Browse the full library →](https://github.com/kogunlowo123/citadel-cloud-management)*
