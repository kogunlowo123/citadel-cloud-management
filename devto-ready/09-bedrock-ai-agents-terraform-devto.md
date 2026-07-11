---
title: "Building Production AI Agents on AWS Bedrock with Terraform"
published: true
description: "Deploy a production AWS Bedrock AI agent with knowledge base (RAG), Lambda action groups, OpenSearch Serverless vector store, and proper IAM — all with Terraform."
tags: aws, terraform, ai, bedrock
series: "Citadel Cloud Management: 100 Free Terraform Guides"
canonical_url: https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/09-bedrock-ai-agents-terraform.md
cover_image: ""
---

AWS Bedrock agents orchestrate foundation models with real-world data and actions. This guide deploys a production Bedrock agent with knowledge base, action groups, and proper IAM using Terraform.

## Architecture

```
User Request
    │
    ▼
Bedrock Agent
    ├── Knowledge Base (RAG) ──► S3 + OpenSearch Serverless
    ├── Action Groups ──────────► Lambda Functions
    └── Foundation Model: Claude Sonnet 5
```

## Bedrock Platform Module

```hcl
module "bedrock_platform" {
  source = "github.com/kogunlowo123/terraform-aws-bedrock-platform"

  agent_name        = "enterprise-assistant"
  foundation_model  = "anthropic.claude-sonnet-4-6-20250731-v1:0"
  agent_instruction = file("${path.module}/instructions/agent-instructions.txt")

  enable_knowledge_base        = true
  knowledge_base_name          = "enterprise-knowledge"
  knowledge_base_s3_bucket_arn = aws_s3_bucket.knowledge_docs.arn
  embedding_model              = "amazon.titan-embed-text-v2:0"

  opensearch_collection_name = "bedrock-kb"
  vector_dimension           = 1024

  action_groups = {
    "database-query" = {
      lambda_arn  = module.db_query_lambda.lambda_function_arn
      api_schema  = file("${path.module}/schemas/database-api.json")
      description = "Query the enterprise database for customer and order data"
    }
    "crm-integration" = {
      lambda_arn  = module.crm_lambda.lambda_function_arn
      api_schema  = file("${path.module}/schemas/crm-api.json")
      description = "Create and update CRM records"
    }
  }

  tags = local.tags
}
```

## Knowledge Base (RAG)

```hcl
resource "aws_bedrockagent_knowledge_base" "main" {
  name        = "enterprise-knowledge-base"
  role_arn    = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = "bedrock-knowledge-base-default-index"
      metadata_field    = "AMAZON_BEDROCK_METADATA"
      text_field        = "AMAZON_BEDROCK_TEXT_CHUNK"
      vector_field      = "bedrock-knowledge-base-default-vector"
    }
  }
}

resource "aws_bedrockagent_data_source" "s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  name              = "enterprise-s3-source"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.knowledge_docs.arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "HIERARCHICAL"
      hierarchical_chunking_configuration {
        level_configurations {
          max_tokens = 1500
        }
        level_configurations {
          max_tokens = 300
        }
        overlap_tokens = 60
      }
    }
  }
}
```

## OpenSearch Serverless Vector Store

```hcl
resource "aws_opensearchserverless_collection" "kb" {
  name = "bedrock-kb"
  type = "VECTORSEARCH"
}

resource "aws_opensearchserverless_access_policy" "kb" {
  name = "bedrock-kb-access"
  type = "data"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "index"
        Resource     = ["index/bedrock-kb/*"]
        Permission   = ["aoss:CreateIndex", "aoss:UpdateIndex", "aoss:DescribeIndex",
                        "aoss:ReadDocument", "aoss:WriteDocument"]
      }
    ]
    Principal = [aws_iam_role.bedrock_kb.arn]
  }])
}

resource "aws_opensearchserverless_security_policy" "kb_encryption" {
  name   = "bedrock-kb-enc"
  type   = "encryption"
  policy = jsonencode({
    Rules  = [{ ResourceType = "collection", Resource = ["collection/bedrock-kb"] }]
    AWSOwnedKey = true
  })
}
```

## Lambda Action Group

```hcl
module "db_query_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 6.0"

  function_name = "${var.prefix}-bedrock-db-action"
  description   = "Bedrock action group — database queries"
  handler       = "index.handler"
  runtime       = "python3.12"
  source_path   = "./lambda/db-action"
  timeout       = 30
  memory_size   = 512

  environment_variables = {
    DB_SECRET_ARN = aws_secretsmanager_secret.db.arn
    DB_CLUSTER_ARN = aws_rds_cluster.main.arn
  }

  attach_policies    = true
  policies = ["arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"]

  attach_policy_statements = true
  policy_statements = {
    bedrock_invoke = {
      effect    = "Allow"
      actions   = ["rds-data:ExecuteStatement"]
      resources = [aws_rds_cluster.main.arn]
    }
    secrets = {
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [aws_secretsmanager_secret.db.arn]
    }
  }
}

# Allow Bedrock to invoke the Lambda
resource "aws_lambda_permission" "bedrock_action" {
  statement_id  = "AllowBedrock"
  action        = "lambda:InvokeFunction"
  function_name = module.db_query_lambda.lambda_function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.main.agent_arn
}
```

## Bedrock Agent

```hcl
resource "aws_bedrockagent_agent" "main" {
  agent_name              = "enterprise-assistant"
  agent_resource_role_arn = aws_iam_role.bedrock_agent.arn
  foundation_model        = "anthropic.claude-sonnet-4-6-20250731-v1:0"
  idle_session_ttl_in_seconds = 600
  description             = "Enterprise AI assistant with knowledge base and CRM access"

  instruction = <<-EOT
    You are an enterprise assistant with access to a knowledge base and the CRM system.
    Answer questions using the knowledge base. Create/update CRM records when requested.
    Always cite sources from the knowledge base. Never guess — use your tools.
  EOT
}

resource "aws_bedrockagent_agent_knowledge_base_association" "main" {
  agent_id             = aws_bedrockagent_agent.main.agent_id
  description          = "Enterprise knowledge base"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.main.id
  knowledge_base_state = "ENABLED"
}

resource "aws_bedrockagent_agent_action_group" "db_query" {
  agent_id          = aws_bedrockagent_agent.main.agent_id
  agent_version     = "DRAFT"
  action_group_name = "database-query"

  action_group_executor {
    lambda = module.db_query_lambda.lambda_function_arn
  }

  api_schema {
    payload = file("${path.module}/schemas/database-api.json")
  }
}

# Prepare and create alias for production
resource "aws_bedrockagent_agent_alias" "prod" {
  agent_id         = aws_bedrockagent_agent.main.agent_id
  agent_alias_name = "prod"
  description      = "Production alias"
}
```

## IAM Role for Bedrock Agent

```hcl
resource "aws_iam_role" "bedrock_agent" {
  name = "${var.prefix}-bedrock-agent-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_agent" {
  name = "bedrock-agent-policy"
  role = aws_iam_role.bedrock_agent.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:*::foundation-model/*"
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve"]
        Resource = aws_bedrockagent_knowledge_base.main.arn
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [
          module.db_query_lambda.lambda_function_arn,
          module.crm_lambda.lambda_function_arn
        ]
      }
    ]
  })
}
```

## Key Configuration Decisions

| Decision | Recommendation | Why |
|----------|---------------|-----|
| Chunking | HIERARCHICAL (1500/300 tokens) | Better retrieval accuracy for long docs |
| Vector model | titan-embed-text-v2 | 1024 dims, best cost/quality for English |
| Session TTL | 600s | Balance memory cost vs UX |
| Agent version | DRAFT → alias | Never point traffic directly at DRAFT |
| OpenSearch | Serverless (VECTORSEARCH) | No cluster management for RAG |

## Production Checklist

- [ ] Agent instruction is specific and role-bound (prevent prompt injection)
- [ ] Lambda action group validates all Bedrock-supplied parameters
- [ ] S3 bucket has versioning + encryption for knowledge base source
- [ ] OpenSearch access policy is least-privilege (specific index only)
- [ ] CloudWatch Logs enabled on Lambda for action group debugging
- [ ] Agent alias pinned to a tested version (not DRAFT in production)
- [ ] IAM role condition on `bedrock.amazonaws.com` uses `aws:SourceAccount`
- [ ] Bedrock model access enabled in your region before deploying
- [ ] Knowledge base sync scheduled (EventBridge rule → `aws bedrock-agent start-ingestion-job`)
- [ ] Test harness validates retrieval accuracy before production cutover

## Full Repository

All Terraform code is MIT licensed: [github.com/kogunlowo123/citadel-cloud-management](https://github.com/kogunlowo123/citadel-cloud-management)

Part of the **Citadel Cloud Management** series — 100+ production Terraform guides, no paywall.
