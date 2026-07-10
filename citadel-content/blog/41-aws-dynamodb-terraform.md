# AWS DynamoDB with Terraform: NoSQL at Scale

**Pillar:** AWS Infrastructure
**SEO Target:** aws dynamodb terraform production global tables streams single table design
**Word Count:** ~1500

DynamoDB is AWS's managed NoSQL database — millisecond latency at any scale, no capacity planning for on-demand mode, fully managed. This guide covers production DynamoDB patterns: single-table design, Global Tables for multi-region, DynamoDB Streams with Lambda, and point-in-time recovery.

## Table Design

```hcl
resource "aws_dynamodb_table" "main" {
  name         = "${var.prefix}-main"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "PK"
  range_key = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  attribute {
    name = "GSI2PK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "GSI2"
    hash_key        = "GSI2PK"
    projection_type = "KEYS_ONLY"
  }

  ttl {
    attribute_name = "ExpiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  deletion_protection_enabled = var.environment == "prod"

  tags = var.tags
}
```

## Global Tables (Multi-Region)

```hcl
resource "aws_dynamodb_table" "global" {
  name             = "${var.prefix}-global"
  billing_mode     = "PAY_PER_REQUEST"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  hash_key         = "PK"
  range_key        = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  replica {
    region_name = "eu-west-1"
  }

  replica {
    region_name = "ap-southeast-1"
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}
```

## DAX Cluster for Microsecond Reads

```hcl
resource "aws_dax_cluster" "main" {
  cluster_name       = "${var.prefix}-dax"
  iam_role_arn       = aws_iam_role.dax.arn
  node_type          = "dax.r5.large"
  replication_factor = var.environment == "prod" ? 3 : 1

  server_side_encryption {
    enabled = true
  }

  subnet_group_name = aws_dax_subnet_group.main.name
  security_group_ids = [aws_security_group.dax.id]

  parameter_group_name = aws_dax_parameter_group.main.name

  tags = var.tags
}
```

## Streams + Lambda Processor

```hcl
resource "aws_lambda_event_source_mapping" "dynamodb_stream" {
  event_source_arn  = aws_dynamodb_table.main.stream_arn
  function_name     = aws_lambda_function.stream_processor.arn
  starting_position = "TRIM_HORIZON"

  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
  parallelization_factor             = 5
  maximum_retry_attempts             = 3
  bisect_batch_on_function_error     = true

  function_response_types = ["ReportBatchItemFailures"]

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.stream_dlq.arn
    }
  }
}
```

## Access Pattern IAM

```hcl
resource "aws_iam_role_policy" "app_dynamodb" {
  name = "dynamodb-access"
  role = var.app_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:TransactWriteItems",
          "dynamodb:TransactGetItems"
        ]
        Resource = [
          aws_dynamodb_table.main.arn,
          "${aws_dynamodb_table.main.arn}/index/*"
        ]
      }
    ]
  })
}
```

## Production Checklist

- [ ] PAY_PER_REQUEST billing (no capacity planning for variable workloads)
- [ ] Point-in-time recovery enabled (35-day window)
- [ ] KMS encryption with customer-managed key
- [ ] Streams with NEW_AND_OLD_IMAGES (needed for change data capture)
- [ ] Lambda stream processor with bisect-on-error and DLQ
- [ ] TTL for session/cache data (automatic expiry, no storage costs)
- [ ] Global Tables for multi-region active-active (same API, automatic replication)
- [ ] DAX for microsecond read latency on hot paths
- [ ] GSIs designed around your access patterns upfront (cannot change keys post-creation)
- [ ] deletion_protection enabled in production

DynamoDB's single-table design is counter-intuitive but powerful — multiple entity types in one table with PK/SK prefixes (USER#123, ORDER#456) eliminates joins and scales to millions of TPS.
