# AWS Step Functions with Terraform: Orchestrating Complex Workflows

**Pillar:** AWS Infrastructure
**SEO Target:** aws step functions terraform workflow orchestration lambda parallel saga pattern
**Word Count:** ~1500

AWS Step Functions orchestrates Lambda functions and other services into reliable workflows. Automatic retry, catch, and parallel execution replace complex Lambda-to-Lambda chaining. This guide implements production workflows with Terraform.

## Standard Workflow with Error Handling

```hcl
resource "aws_sfn_state_machine" "order_processing" {
  name     = "${var.prefix}-order-processing"
  role_arn = aws_iam_role.step_functions.arn
  type     = "STANDARD"

  definition = jsonencode({
    Comment = "Order processing workflow with saga pattern"
    StartAt = "ValidateOrder"
    States = {
      ValidateOrder = {
        Type     = "Task"
        Resource = aws_lambda_function.validate_order.arn
        Retry = [{
          ErrorEquals    = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
          IntervalSeconds = 2
          MaxAttempts    = 3
          BackoffRate    = 2
        }]
        Catch = [{
          ErrorEquals = ["OrderValidationError"]
          Next        = "OrderFailed"
          ResultPath  = "$.error"
        }]
        Next = "ProcessPayment"
      }
      ProcessPayment = {
        Type     = "Task"
        Resource = aws_lambda_function.process_payment.arn
        Retry = [{
          ErrorEquals    = ["PaymentGatewayError"]
          IntervalSeconds = 5
          MaxAttempts    = 2
          BackoffRate    = 1.5
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "CompensateOrder"
          ResultPath  = "$.paymentError"
        }]
        Next = "FulfillOrder"
      }
      FulfillOrder = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "NotifyCustomer"
            States = {
              NotifyCustomer = {
                Type     = "Task"
                Resource = aws_lambda_function.notify_customer.arn
                End      = true
              }
            }
          },
          {
            StartAt = "UpdateInventory"
            States = {
              UpdateInventory = {
                Type     = "Task"
                Resource = aws_lambda_function.update_inventory.arn
                End      = true
              }
            }
          }
        ]
        Next = "OrderComplete"
      }
      CompensateOrder = {
        Type     = "Task"
        Resource = aws_lambda_function.compensate_order.arn
        Next     = "OrderFailed"
      }
      OrderComplete = { Type = "Succeed" }
      OrderFailed   = { Type = "Fail" }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  tracing_configuration {
    enabled = true
  }

  tags = var.tags
}
```

## Express Workflow for High-Throughput

```hcl
resource "aws_sfn_state_machine" "event_router" {
  name     = "${var.prefix}-event-router"
  role_arn = aws_iam_role.step_functions.arn
  type     = "EXPRESS"

  definition = jsonencode({
    StartAt = "RouteEvent"
    States = {
      RouteEvent = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.eventType"
            StringEquals  = "order.created"
            Next          = "ProcessOrder"
          },
          {
            Variable      = "$.eventType"
            StringEquals  = "user.registered"
            Next          = "OnboardUser"
          }
        ]
        Default = "IgnoreEvent"
      }
      ProcessOrder  = { Type = "Task", Resource = aws_lambda_function.process_order.arn,  End = true }
      OnboardUser   = { Type = "Task", Resource = aws_lambda_function.onboard_user.arn,   End = true }
      IgnoreEvent   = { Type = "Pass", End = true }
    }
  })
}
```

## Production Checklist

- [ ] Saga pattern: compensating transactions on payment failure
- [ ] Parallel state for independent tasks (notify + inventory simultaneously)
- [ ] Retry with exponential backoff on transient Lambda errors
- [ ] Catch for specific business errors with ResultPath to preserve input
- [ ] STANDARD workflow for long-running (up to 1 year); EXPRESS for high-throughput (< 5 min)
- [ ] CloudWatch logging with include_execution_data=true for debugging
- [ ] X-Ray tracing across workflow steps
- [ ] EventBridge trigger: start execution on SQS/SNS events
