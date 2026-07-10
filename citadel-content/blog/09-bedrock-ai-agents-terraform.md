# Building Production AI Agents on AWS Bedrock with Terraform

**Pillar:** AI/ML Engineering
**SEO Target:** "aws bedrock terraform agents", "bedrock claude terraform production"
**Word Count:** ~2,200

---

AWS Bedrock has changed how enterprises build AI applications. Instead of managing model infrastructure, you call an API. But building a production AI agent on Bedrock — with knowledge bases, action groups, memory, and proper IAM — is still a non-trivial infrastructure problem.

This guide covers the Terraform patterns I use for production Bedrock deployments.

## The Architecture

```
User Request
    │
    ▼
Bedrock Agent
    ├── Knowledge Base (RAG) ──► S3 + OpenSearch Serverless
    ├── Action Groups ──────────► Lambda Functions
    └── Model: Claude Sonnet 5
```

The agent orchestrates between a knowledge base (for context retrieval) and action groups (for real-world operations like querying databases or calling APIs).

## Deploying the Bedrock Platform

```hcl
module "bedrock_platform" {
  source = "github.com/kogunlowo123/terraform-aws-bedrock-platform"

  # Agent configuration
  agent_name        = "enterprise-assistant"
  foundation_model  = "anthropic.claude-sonnet-4-6-20250731-v1:0"
  agent_instruction = file("${path.module}/instructions/agent-instructions.txt")

  # Knowledge base
  enable_knowledge_base        = true
  knowledge_base_name          = "enterprise-knowledge"
  knowledge_base_s3_bucket_arn = aws_s3_bucket.knowledge_docs.arn
  embedding_model              = "amazon.titan-embed-text-v2:0"

  # Vector store (OpenSearch Serverless)
  opensearch_collection_name   = "bedrock-kb"
  vector_dimension             = 1024

  # Action groups
  action_groups = {
    "database-query" = {
      lambda_arn   = module.db_query_lambda.lambda_function_arn
      api_schema   = file("${path.module}/schemas/database-api.json")
      description  = "Query the enterprise database for customer and order data"
    }
    "crm-integration" = {
      lambda_arn   = module.crm_lambda.lambda_function_arn
      api_schema   = file("${path.module}/schemas/crm-api.json")
      description  = "Create and update CRM records"
    }
  }

  tags = local.tags
}
```

## Knowledge Base Setup

The knowledge base uses a RAG (Retrieval-Augmented Generation) pattern:

```hcl
resource "aws_bedrockagent_knowledge_base" "main" {
  name        = "enterprise-knowledge-base"
  role_arn    = aws_iam_role.bedrock_kb.arn
  description = "Enterprise knowledge base for the AI assistant"

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
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }
}

# Data source pointing to S3
resource "aws_bedrockagent_data_source" "docs" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  name              = "enterprise-docs"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn     = aws_s3_bucket.knowledge_docs.arn
      inclusion_prefixes = ["docs/", "policies/", "runbooks/"]
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

Hierarchical chunking is the right choice for long documents — it preserves context better than fixed-size chunks.

## Action Group Lambda

Action groups let the agent take real actions. Here's a database query action:

```python
import json
import boto3

def handler(event, context):
    action = event.get("actionGroup")
    api_path = event.get("apiPath")
    parameters = event.get("parameters", [])
    
    param_dict = {p["name"]: p["value"] for p in parameters}
    
    if api_path == "/query-customers":
        customer_id = param_dict.get("customerId")
        result = query_customer_database(customer_id)
        return {
            "messageVersion": "1.0",
            "response": {
                "actionGroup": action,
                "apiPath": api_path,
                "httpStatusCode": 200,
                "responseBody": {
                    "application/json": {
                        "body": json.dumps(result)
                    }
                }
            }
        }
```

## IAM Configuration

Bedrock agents need specific IAM permissions:

```hcl
resource "aws_iam_role" "bedrock_agent" {
  name = "bedrock-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "bedrock.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
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
        Resource = "arn:aws:bedrock:*::foundation-model/anthropic.claude-*"
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve"]
        Resource = aws_bedrockagent_knowledge_base.main.arn
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [for ag in var.action_group_lambdas : ag]
      }
    ]
  })
}
```

## Monitoring and Observability

```hcl
# CloudWatch dashboard for agent metrics
resource "aws_cloudwatch_dashboard" "bedrock" {
  dashboard_name = "bedrock-agent-metrics"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Bedrock", "InvocationLatency", "ModelId", "anthropic.claude-sonnet-4-6-20250731-v1:0"],
            ["AWS/Bedrock", "InvocationThrottles", "ModelId", "anthropic.claude-sonnet-4-6-20250731-v1:0"]
          ]
          period = 300
          stat   = "p99"
          title  = "Bedrock Latency and Throttles"
        }
      }
    ]
  })
}
```

## Cost Optimization

- Use Claude Haiku 4.5 for simple classification/routing, Sonnet for complex reasoning
- Enable prompt caching for system prompts (up to 90% cost reduction on repeated context)
- Set knowledge base retrieval to max 5 chunks — more chunks = higher cost with diminishing returns
- Use Bedrock Guardrails to prevent hallucinated responses before they reach users

## Module

[terraform-aws-bedrock-platform](https://github.com/kogunlowo123/terraform-aws-bedrock-platform) — complete production Bedrock deployment including agents, knowledge bases, and monitoring.
