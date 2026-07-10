# AWS Bedrock Knowledge Base with Terraform: RAG Pipeline in Production

**Pillar:** AI/ML Engineering
**SEO Target:** aws bedrock knowledge base rag terraform production
**Word Count:** ~1700

AWS Bedrock Knowledge Bases provides managed Retrieval-Augmented Generation (RAG). You connect a data source (S3, Confluence, SharePoint, Salesforce), Bedrock handles chunking, embedding, and vector storage, and your agents retrieve relevant context automatically. This guide deploys a production RAG pipeline with Terraform.

## Architecture

```
S3 Data Source (PDFs, docs, HTML)
        ↓
Bedrock Knowledge Base
   ├── Data Ingestion Job (chunking + embedding)
   ├── Embeddings: Titan Embeddings v2
   └── Vector Store: OpenSearch Serverless
        ↓
Bedrock Agent (Claude 3.5 Sonnet)
        ↓
Application (API Gateway + Lambda)
```

## OpenSearch Serverless Collection

```hcl
resource "aws_opensearchserverless_security_policy" "encryption" {
  name   = "${var.prefix}-kb-encryption"
  type   = "encryption"
  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${var.prefix}-kb-*"]
    }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name   = "${var.prefix}-kb-network"
  type   = "network"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.prefix}-kb-*"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${var.prefix}-kb-*"]
      }
    ]
    AllowFromPublic = false
    SourceVPCEs = [aws_opensearchserverless_vpc_endpoint.main.id]
  }])
}

resource "aws_opensearchserverless_access_policy" "main" {
  name   = "${var.prefix}-kb-access"
  type   = "data"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.prefix}-kb-*"]
        Permission   = ["aoss:CreateCollectionItems", "aoss:DeleteCollectionItems", "aoss:UpdateCollectionItems", "aoss:DescribeCollectionItems"]
      },
      {
        ResourceType = "index"
        Resource     = ["index/${var.prefix}-kb-*/*"]
        Permission   = ["aoss:CreateIndex", "aoss:DeleteIndex", "aoss:UpdateIndex", "aoss:DescribeIndex", "aoss:ReadDocument", "aoss:WriteDocument"]
      }
    ]
    Principal = [
      aws_iam_role.bedrock_kb.arn,
      data.aws_caller_identity.current.arn
    ]
  }])
}

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

## OpenSearch Index

```hcl
resource "opensearch_index" "kb" {
  name                  = "bedrock-knowledge-base"
  number_of_shards      = "2"
  number_of_replicas    = "0"
  index_knn             = true
  index_knn_algo_param_ef_search = "512"

  mappings = jsonencode({
    properties = {
      AMAZON_BEDROCK_METADATA = {
        type  = "text"
        index = false
      }
      AMAZON_BEDROCK_TEXT_CHUNK = {
        type = "text"
      }
      bedrock-knowledge-base-default-vector = {
        type      = "knn_vector"
        dimension = 1536
        method = {
          name       = "hnsw"
          engine     = "faiss"
          space_type = "l2"
          parameters = {
            ef_construction = 512
            m               = 16
          }
        }
      }
    }
  })

  lifecycle {
    ignore_changes = [mappings]
  }
}
```

## Bedrock IAM Role

```hcl
resource "aws_iam_role" "bedrock_kb" {
  name = "${var.prefix}-bedrock-kb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb" {
  name = "bedrock-kb-policy"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.kb_data.arn,
          "${aws_s3_bucket.kb_data.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0"
      },
      {
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = aws_opensearchserverless_collection.kb.arn
      }
    ]
  })
}
```

## Knowledge Base Resource

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

  tags = var.tags
}
```

## Data Source

```hcl
resource "aws_bedrockagent_data_source" "s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  name              = "${var.prefix}-s3-docs"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn          = aws_s3_bucket.kb_data.arn
      inclusion_prefixes  = ["documents/", "faqs/"]
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

## Bedrock Agent

```hcl
resource "aws_bedrockagent_agent" "main" {
  agent_name              = "${var.prefix}-agent"
  agent_resource_role_arn = aws_iam_role.bedrock_agent.arn
  foundation_model        = "anthropic.claude-3-5-sonnet-20241022-v2:0"
  idle_session_ttl_in_seconds = 600

  instruction = var.agent_instruction

  tags = var.tags
}

resource "aws_bedrockagent_agent_knowledge_base_association" "main" {
  agent_id             = aws_bedrockagent_agent.main.agent_id
  description          = "Main knowledge base"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.main.id
  knowledge_base_state = "ENABLED"
}
```

## Ingestion Trigger Lambda

```hcl
resource "aws_lambda_function" "ingest_trigger" {
  function_name = "${var.prefix}-kb-ingest"
  role          = aws_iam_role.ingest_trigger.arn
  runtime       = "python3.12"
  handler       = "index.handler"
  filename      = data.archive_file.ingest_trigger.output_path

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.main.id
      DATA_SOURCE_ID    = aws_bedrockagent_data_source.s3.data_source_id
    }
  }

  timeout = 60
}

# Trigger ingestion when new files land in S3
resource "aws_s3_bucket_notification" "kb_data" {
  bucket = aws_s3_bucket.kb_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "documents/"
  }
}
```

## Outputs

```hcl
output "knowledge_base_id" {
  value = aws_bedrockagent_knowledge_base.main.id
}

output "agent_id" {
  value = aws_bedrockagent_agent.main.agent_id
}

output "opensearch_endpoint" {
  value = aws_opensearchserverless_collection.kb.collection_endpoint
}

output "kb_data_bucket" {
  value = aws_s3_bucket.kb_data.bucket
}
```

## Production Checklist

- [ ] OpenSearch Serverless with VPC endpoint (no public access)
- [ ] Encryption policy with AWS-owned KMS key
- [ ] Bedrock role with SourceArn condition (prevents confused deputy)
- [ ] Hierarchical chunking (1500/300 tokens) for better retrieval
- [ ] S3 trigger for automatic ingestion on new document upload
- [ ] Knowledge base data source with inclusion prefixes
- [ ] Agent with Claude 3.5 Sonnet for best retrieval+generation quality
- [ ] STANDBY_REPLICAS enabled for production collections
- [ ] CloudWatch logging on all Lambda functions

Bedrock Knowledge Bases with OpenSearch Serverless gives you a fully managed RAG system — no embedding servers, no vector DB to maintain, automatic scaling — with enterprise security controls throughout.
