# AWS API Gateway REST API with Terraform: Production HTTP Endpoints

**Pillar:** AWS Infrastructure
**SEO Target:** aws api gateway rest api terraform production lambda authorizer
**Word Count:** ~1500

AWS API Gateway REST API provides managed HTTP endpoints for Lambda, ECS, and HTTP integrations. This guide deploys a production API with Lambda authorizer, usage plans, and WAF.

## API Gateway with Lambda Authorizer

```hcl
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.prefix}-api"
  description = "Production REST API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_method" "get_orders" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt.id
}

resource "aws_api_gateway_authorizer" "jwt" {
  name                   = "jwt-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.main.id
  authorizer_uri         = aws_lambda_function.authorizer.invoke_arn
  authorizer_credentials = aws_iam_role.invocation_role.arn
  identity_source        = "method.request.header.Authorization"
  type                   = "TOKEN"
  authorizer_result_ttl_in_seconds = 300
}
```

## Usage Plans with API Keys

```hcl
resource "aws_api_gateway_usage_plan" "standard" {
  name = "${var.prefix}-standard"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.v1.stage_name
  }

  quota_settings {
    limit  = 10000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 500
    rate_limit  = 100
  }
}
```

## WAF Association

```hcl
resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_api_gateway_stage.v1.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
```

## Production Checklist

- [ ] Lambda authorizer with 5-minute token cache (reduces Lambda invocations 99%)
- [ ] Usage plans + API keys for rate limiting per client
- [ ] WAF association on production stage
- [ ] CloudWatch logs at INFO level on stage
- [ ] X-Ray tracing enabled
- [ ] Custom domain with Route 53 + ACM certificate
- [ ] VPC endpoint for private APIs
