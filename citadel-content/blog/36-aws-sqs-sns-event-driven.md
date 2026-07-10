# AWS SQS and SNS: Event-Driven Architecture with Terraform

**Pillar:** AWS Infrastructure
**SEO Target:** aws sqs sns terraform event driven architecture fanout dead letter queue
**Word Count:** ~1600

SQS and SNS are the cornerstones of event-driven architecture on AWS. SNS fans out to multiple subscribers; SQS buffers work for reliable async processing. Together they decouple producers from consumers entirely. This guide implements production patterns: fanout, dead-letter queues, FIFO ordering, and Lambda integration.

## SNS Topic with Fanout

```hcl
resource "aws_sns_topic" "orders" {
  name              = "${var.prefix}-orders"
  kms_master_key_id = aws_kms_key.sns.arn

  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget     = 20
        maxDelayTarget     = 20
        numRetries         = 3
        numMaxDelayRetries = 0
        numNoDelayRetries  = 0
        numMinDelayRetries = 0
        backoffFunction    = "linear"
      }
    }
  })

  tags = var.tags
}

resource "aws_sns_topic_policy" "orders" {
  arn = aws_sns_topic.orders.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPublish"
        Effect = "Allow"
        Principal = {
          AWS = var.publisher_role_arns
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.orders.arn
      }
    ]
  })
}
```

## SQS Queues with DLQ

```hcl
resource "aws_sqs_queue" "fulfillment_dlq" {
  name                      = "${var.prefix}-fulfillment-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.sqs.id
  tags                      = var.tags
}

resource "aws_sqs_queue" "fulfillment" {
  name                       = "${var.prefix}-fulfillment"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20
  kms_master_key_id          = aws_kms_key.sqs.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.fulfillment_dlq.arn
    maxReceiveCount     = 3
  })

  tags = var.tags
}

resource "aws_sqs_queue" "notifications_dlq" {
  name                      = "${var.prefix}-notifications-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.sqs.id
  tags                      = var.tags
}

resource "aws_sqs_queue" "notifications" {
  name                       = "${var.prefix}-notifications"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20
  kms_master_key_id          = aws_kms_key.sqs.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = 5
  })

  tags = var.tags
}
```

## SNS → SQS Subscriptions (Fanout)

```hcl
resource "aws_sns_topic_subscription" "orders_to_fulfillment" {
  topic_arn            = aws_sns_topic.orders.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.fulfillment.arn
  raw_message_delivery = true

  filter_policy = jsonencode({
    order_type = ["standard", "express"]
    status     = ["new"]
  })
}

resource "aws_sns_topic_subscription" "orders_to_notifications" {
  topic_arn            = aws_sns_topic.orders.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.notifications.arn
  raw_message_delivery = true

  filter_policy = jsonencode({
    status = ["new", "shipped", "delivered", "cancelled"]
  })
}

resource "aws_sqs_queue_policy" "fulfillment" {
  queue_url = aws_sqs_queue.fulfillment.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.fulfillment.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_sns_topic.orders.arn
        }
      }
    }]
  })
}
```

## FIFO Queue for Ordered Processing

```hcl
resource "aws_sqs_queue" "payments_fifo" {
  name                        = "${var.prefix}-payments.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"

  visibility_timeout_seconds = 300
  kms_master_key_id          = aws_kms_key.sqs.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.payments_dlq.arn
    maxReceiveCount     = 3
  })

  tags = var.tags
}
```

## Lambda Consumer

```hcl
resource "aws_lambda_event_source_mapping" "fulfillment" {
  event_source_arn = aws_sqs_queue.fulfillment.arn
  function_name    = aws_lambda_function.fulfillment_processor.arn
  enabled          = true

  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 50
  }
}
```

## DLQ Alarm

```hcl
resource "aws_cloudwatch_metric_alarm" "fulfillment_dlq_depth" {
  alarm_name          = "${var.prefix}-fulfillment-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Fulfillment DLQ has messages — investigate failures"

  dimensions = {
    QueueName = aws_sqs_queue.fulfillment_dlq.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}
```

## Production Checklist

- [ ] All queues KMS-encrypted with customer-managed keys
- [ ] DLQ on every queue with maxReceiveCount ≤ 5
- [ ] Long polling enabled (receive_wait_time_seconds = 20)
- [ ] SNS filter policies to route messages by attribute (reduces consumer load)
- [ ] SQS policy allows SNS publish with ArnEquals condition
- [ ] Lambda with ReportBatchItemFailures (partial batch success)
- [ ] Lambda scaling config to limit max concurrency per queue
- [ ] CloudWatch alarm on DLQ depth (> 0 messages = alert)
- [ ] FIFO queue for payment processing (strict ordering per customer)

The fanout pattern — one SNS publish hits multiple SQS queues — is more reliable than direct service-to-service calls. A downstream service can be down for hours; when it recovers, it drains its queue and catches up. No messages lost.
