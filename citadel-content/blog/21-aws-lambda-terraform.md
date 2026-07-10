# AWS Lambda with Terraform: Serverless Functions in Production

**Pillar:** AWS Infrastructure
**SEO Target:** aws lambda terraform production serverless
**Word Count:** ~1600

AWS Lambda lets you run code without provisioning servers. This guide covers deploying Lambda functions with Terraform including container image packaging, environment variables from Secrets Manager, VPC integration, X-Ray tracing, and Dead Letter Queues.

## Module Structure

```
lambda/
├── main.tf
├── iam.tf
├── monitoring.tf
├── variables.tf
└── outputs.tf
```

## Lambda Function (Container Image)

```hcl
resource "aws_lambda_function" "main" {
  function_name = "${var.name}-${var.environment}"
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:${var.image_tag}"
  role          = aws_iam_role.lambda.arn

  timeout                        = var.timeout
  memory_size                    = var.memory_size
  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      ENVIRONMENT = var.environment
      LOG_LEVEL   = var.log_level
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  ephemeral_storage {
    size = 1024
  }

  tags = var.tags
}
```

## IAM Role

```hcl
resource "aws_iam_role" "lambda" {
  name = "${var.name}-${var.environment}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "secrets" {
  name = "read-secrets"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.secret_arns
    }]
  })
}
```

## Dead Letter Queue

```hcl
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-${var.environment}-dlq"
  message_retention_seconds = 1209600  # 14 days
  kms_master_key_id         = "alias/aws/sqs"

  tags = var.tags
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.dlq.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_lambda_function.main.arn }
      }
    }]
  })
}
```

## CloudWatch Log Group

```hcl
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.main.function_name}"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
}
```

## Function URL (Optional)

```hcl
resource "aws_lambda_function_url" "main" {
  count              = var.enable_function_url ? 1 : 0
  function_name      = aws_lambda_function.main.function_name
  authorization_type = "AWS_IAM"

  cors {
    allow_origins = var.cors_origins
    allow_methods = ["GET", "POST"]
    max_age       = 3600
  }
}
```

## Event Source Mapping (SQS)

```hcl
resource "aws_lambda_event_source_mapping" "sqs" {
  count = var.sqs_trigger_arn != "" ? 1 : 0

  event_source_arn                   = var.sqs_trigger_arn
  function_name                      = aws_lambda_function.main.arn
  batch_size                         = var.sqs_batch_size
  maximum_batching_window_in_seconds = 30

  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = var.sqs_max_concurrency
  }
}
```

## Provisioned Concurrency

```hcl
resource "aws_lambda_provisioned_concurrency_config" "main" {
  count = var.provisioned_concurrency > 0 ? 1 : 0

  function_name                  = aws_lambda_function.main.function_name
  qualifier                      = aws_lambda_alias.live.name
  provisioned_concurrent_executions = var.provisioned_concurrency
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.main.function_name
  function_version = "$LATEST"
}
```

## CloudWatch Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.name}-${var.environment}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.main.function_name
  }

  alarm_actions = [var.sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "throttles" {
  alarm_name          = "${var.name}-${var.environment}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.main.function_name
  }

  alarm_actions = [var.sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.name}-${var.environment}-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = [var.sns_topic_arn]
}
```

## Variables

```hcl
variable "name" { type = string }
variable "environment" { type = string }
variable "ecr_repository_url" { type = string }
variable "image_tag" { type = string; default = "latest" }
variable "timeout" { type = number; default = 30 }
variable "memory_size" { type = number; default = 512 }
variable "reserved_concurrency" { type = number; default = -1 }
variable "provisioned_concurrency" { type = number; default = 0 }
variable "private_subnet_ids" { type = list(string); default = [] }
variable "secret_arns" { type = list(string); default = [] }
variable "sqs_trigger_arn" { type = string; default = "" }
variable "sqs_batch_size" { type = number; default = 10 }
variable "sqs_max_concurrency" { type = number; default = 5 }
variable "enable_function_url" { type = bool; default = false }
variable "cors_origins" { type = list(string); default = ["*"] }
variable "log_level" { type = string; default = "INFO" }
variable "kms_key_arn" { type = string; default = null }
variable "sns_topic_arn" { type = string }
variable "tags" { type = map(string); default = {} }
```

## Production Checklist

- [ ] Container image from ECR (not zip packages for production)
- [ ] VPC enabled for database access
- [ ] X-Ray active tracing enabled
- [ ] Dead Letter Queue for failed invocations
- [ ] CloudWatch alarms for errors, throttles, and DLQ depth
- [ ] Reserved concurrency set to prevent runaway scaling
- [ ] Log group with 30-day retention and encryption
- [ ] Secrets via Secrets Manager (not env vars)
- [ ] Provisioned concurrency for latency-sensitive paths
- [ ] IAM role with least-privilege policies

Lambda with container images, VPC access, and DLQ gives you a serverless compute platform that's observable, secure, and resilient to downstream failures.
