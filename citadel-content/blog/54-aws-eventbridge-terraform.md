# AWS EventBridge with Terraform: Event-Driven Architecture at Scale

**Pillar:** AWS Infrastructure
**SEO Target:** aws eventbridge terraform event bus rules patterns custom events schedule
**Word Count:** ~1500

EventBridge is AWS's serverless event bus. It decouples event producers from consumers with pattern-based routing, scheduled rules, and cross-account event delivery. This guide implements production event-driven patterns with Terraform.

## Custom Event Bus

```hcl
resource "aws_cloudwatch_event_bus" "app" {
  name = "${var.prefix}-events"
  tags = var.tags
}

resource "aws_cloudwatch_event_bus_policy" "app" {
  event_bus_name = aws_cloudwatch_event_bus.app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCrossAccountPublish"
      Effect = "Allow"
      Principal = { AWS = var.publisher_account_ids }
      Action   = "events:PutEvents"
      Resource = aws_cloudwatch_event_bus.app.arn
    }]
  })
}
```

## Event Rules with Pattern Matching

```hcl
resource "aws_cloudwatch_event_rule" "order_created" {
  name           = "${var.prefix}-order-created"
  event_bus_name = aws_cloudwatch_event_bus.app.name
  description    = "Routes order.created events to fulfillment"

  event_pattern = jsonencode({
    source      = ["citadel.orders"]
    detail-type = ["OrderCreated"]
    detail = {
      status = ["PENDING"]
      amount = [{ numeric = [">", 0, "<=", 10000] }]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "order_to_sqs" {
  rule           = aws_cloudwatch_event_rule.order_created.name
  event_bus_name = aws_cloudwatch_event_bus.app.name
  target_id      = "SendToFulfillmentQueue"
  arn            = aws_sqs_queue.fulfillment.arn

  input_transformer {
    input_paths = {
      orderId    = "$.detail.orderId"
      customerId = "$.detail.customerId"
    }
    input_template = <<-JSON
      {
        "orderId": "<orderId>",
        "customerId": "<customerId>",
        "source": "eventbridge"
      }
    JSON
  }
}

resource "aws_cloudwatch_event_target" "order_to_sfn" {
  rule           = aws_cloudwatch_event_rule.order_created.name
  event_bus_name = aws_cloudwatch_event_bus.app.name
  target_id      = "StartOrderWorkflow"
  arn            = aws_sfn_state_machine.order_processing.arn
  role_arn       = aws_iam_role.eventbridge_sfn.arn
}
```

## Scheduled Rules

```hcl
resource "aws_cloudwatch_event_rule" "daily_report" {
  name                = "${var.prefix}-daily-report"
  description         = "Generate daily analytics report at 6am UTC"
  schedule_expression = "cron(0 6 * * ? *)"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "daily_report_lambda" {
  rule      = aws_cloudwatch_event_rule.daily_report.name
  target_id = "TriggerReportLambda"
  arn       = aws_lambda_function.daily_report.arn
}

resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.daily_report.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_report.arn
}
```

## Archive and Replay

```hcl
resource "aws_cloudwatch_event_archive" "app" {
  name             = "${var.prefix}-archive"
  event_source_arn = aws_cloudwatch_event_bus.app.arn
  retention_days   = 30

  event_pattern = jsonencode({
    source = ["citadel.orders", "citadel.users"]
  })
}
```

## Production Checklist

- [ ] Custom event bus per domain (not default bus)
- [ ] Cross-account event bus policy for multi-account architectures
- [ ] Pattern matching: filter on source, detail-type, AND detail fields
- [ ] Input transformer: reshape event before delivering to target
- [ ] Multiple targets per rule (SQS + Step Functions simultaneously)
- [ ] Archive with 30-day retention for event replay during incidents
- [ ] DLQ on each target (failed deliveries go to SQS for investigation)
- [ ] Scheduled rules replace cron-on-EC2 patterns
