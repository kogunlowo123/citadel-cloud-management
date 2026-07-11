# AWS Lambda SnapStart with Terraform: Sub-Second Cold Starts in Production

**Pillar:** AWS Infrastructure
**SEO Target:** aws lambda snapstart terraform, lambda snapstart java terraform production
**Word Count:** ~1,800

Lambda SnapStart eliminates cold start latency for Java functions by taking a snapshot of the initialized execution environment and restoring it on invocation. For Java 11+ functions using Corretto, this reduces cold starts from 5–10 seconds to under 300ms. This guide deploys SnapStart-enabled Lambda functions with Terraform, covering the restore hook, lifecycle policies, and version aliases for blue/green deployments.

## How SnapStart Works

```
Deploy → Init phase runs once → Snapshot taken
         ↓
Invoke  → Restore from snapshot → Handler executes
         (< 300ms vs 5–10s cold start)
```

SnapStart runs your `@SnapStart` initialization code once, takes a Firecracker microVM snapshot, and restores that snapshot on each cold start instead of re-running initialization. The key constraint: functions must handle uniqueness on restore (UUIDs, random seeds, TCP connections).

## Lambda Function with SnapStart

```hcl
resource "aws_lambda_function" "api_handler" {
  function_name = "${var.prefix}-api-handler"
  role          = aws_iam_role.lambda.arn
  runtime       = "java21"
  handler       = "com.citadel.ApiHandler::handleRequest"
  filename      = data.archive_file.lambda_jar.output_path
  timeout       = 30
  memory_size   = 1024

  snap_start {
    apply_on = "PublishedVersions"
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
      TABLE_NAME  = aws_dynamodb_table.main.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags
}
```

**Critical constraint:** SnapStart only applies to **published versions**, not `$LATEST`. You must publish and alias.

## Published Version + Alias (Required)

```hcl
resource "aws_lambda_function_event_invoke_config" "api_handler" {
  function_name = aws_lambda_function.api_handler.function_name
  qualifier     = "$LATEST"

  maximum_event_age_in_seconds = 60
  maximum_retry_attempts       = 0
}

resource "aws_lambda_version" "api_handler" {
  function_name = aws_lambda_function.api_handler.function_name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Production alias with SnapStart"
  function_name    = aws_lambda_function.api_handler.function_name
  function_version = aws_lambda_version.api_handler.version
}

# Weighted alias for blue/green (0% → 100% over deploy)
resource "aws_lambda_alias" "canary" {
  name             = "canary"
  description      = "Canary deployment alias"
  function_name    = aws_lambda_function.api_handler.function_name
  function_version = aws_lambda_version.api_handler.version

  routing_config {
    additional_version_weights = {
      (aws_lambda_version.api_handler.version) = 0.1  # 10% traffic
    }
  }
}
```

## API Gateway Pointing to Alias

```hcl
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.prefix}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["https://${var.domain}"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 86400
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_alias.live.invoke_arn  # alias, not $LATEST
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
    })
  }

  default_route_settings {
    throttling_burst_limit   = 1000
    throttling_rate_limit    = 500
    detailed_metrics_enabled = true
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
```

## IAM Role

```hcl
resource "aws_iam_role" "lambda" {
  name = "${var.prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "lambda_custom" {
  name = "lambda-custom"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]
        Resource = [aws_dynamodb_table.main.arn, "${aws_dynamodb_table.main.arn}/index/*"]
      }
    ]
  })
}
```

## CloudWatch Monitoring for SnapStart

```hcl
resource "aws_cloudwatch_metric_alarm" "restore_duration" {
  alarm_name          = "${var.prefix}-snapstart-restore-p99"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "RestoreDuration"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "p99"
  threshold           = 500  # Alert if p99 restore > 500ms

  dimensions = {
    FunctionName = aws_lambda_function.api_handler.function_name
    Resource     = "${aws_lambda_function.api_handler.function_name}:${aws_lambda_alias.live.name}"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "init_duration" {
  alarm_name          = "${var.prefix}-lambda-init-p99"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "InitDuration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "p99"
  threshold           = 1000  # If init > 1s, SnapStart restore may be degraded

  dimensions = {
    FunctionName = aws_lambda_function.api_handler.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

## Lifecycle Policy for Version Cleanup

```hcl
resource "aws_lambda_function_event_invoke_config" "live" {
  function_name = aws_lambda_function.api_handler.function_name
  qualifier     = aws_lambda_alias.live.name

  maximum_event_age_in_seconds = 60
  maximum_retry_attempts       = 0
}

# Clean up old versions — keep last 5
resource "null_resource" "version_cleanup" {
  triggers = {
    version = aws_lambda_version.api_handler.version
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws lambda list-versions-by-function \
        --function-name ${aws_lambda_function.api_handler.function_name} \
        --query 'Versions[?Version!=`$LATEST`]|sort_by(@, &Version)[:-5].Version' \
        --output text | \
      xargs -I{} aws lambda delete-function \
        --function-name ${aws_lambda_function.api_handler.function_name} \
        --qualifier {} 2>/dev/null || true
    EOT
  }
}
```

## Variables

```hcl
variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "domain" {
  description = "Application domain for CORS"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
```

## Java SnapStart Restore Hook

Your Java handler needs to handle uniqueness on restore. Add the `@SnapStart` annotation and implement `CRaC`:

```java
// pom.xml dependency
// <dependency>
//   <groupId>software.amazon.lambda</groupId>
//   <artifactId>powertools-logging</artifactId>
// </dependency>

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import org.crac.Core;
import org.crac.Resource;

public class ApiHandler implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse>, Resource {

    private DynamoDbClient dynamoDb;

    public ApiHandler() {
        // Heavy initialization here — runs ONCE before snapshot
        this.dynamoDb = DynamoDbClient.builder()
            .region(Region.of(System.getenv("AWS_REGION")))
            .build();

        // Register for CRaC restore callbacks
        Core.getGlobalContext().register(this);
    }

    @Override
    public void beforeCheckpoint(org.crac.Context<? extends Resource> context) {
        // Close connections before snapshot — TCP state won't survive
        dynamoDb.close();
    }

    @Override
    public void afterRestore(org.crac.Context<? extends Resource> context) {
        // Reinitialize connections after restore
        this.dynamoDb = DynamoDbClient.builder()
            .region(Region.of(System.getenv("AWS_REGION")))
            .build();
        // Re-seed any random number generators
        // Refresh any cached credentials
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent event, Context context) {
        // Normal handler code
        return APIGatewayV2HTTPResponse.builder()
            .withStatusCode(200)
            .build();
    }
}
```

## Production Checklist

- [ ] Runtime is Java 11, 17, or 21 (Corretto) — SnapStart doesn't support other runtimes
- [ ] `apply_on = "PublishedVersions"` — SnapStart only on published versions
- [ ] All invocations target alias, not `$LATEST`
- [ ] `beforeCheckpoint` closes DB connections, open files, TCP sockets
- [ ] `afterRestore` reopens connections and re-seeds randoms
- [ ] `RestoreDuration` p99 alarm set (threshold: 500ms)
- [ ] Version lifecycle policy prevents unbounded version accumulation
- [ ] API Gateway points to alias ARN for SnapStart to apply
- [ ] X-Ray tracing enabled to observe restore vs. init durations

SnapStart is the most impactful Java Lambda optimization available — cutting 5–10 second cold starts to under 300ms with minimal code change. Combined with an alias routing strategy, you get zero-downtime deployments and production-grade observability.
