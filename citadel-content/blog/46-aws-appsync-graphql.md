# AWS AppSync GraphQL API with Terraform

**Pillar:** AWS Infrastructure
**SEO Target:** aws appsync graphql terraform lambda resolvers subscriptions
**Word Count:** ~1500

AWS AppSync is a managed GraphQL service that connects your API to DynamoDB, Lambda, RDS, HTTP, and Elasticsearch in one schema. Real-time subscriptions, offline sync via Amplify, and per-resolver authorization make it the right choice for mobile/web APIs with complex data requirements. This guide deploys AppSync with Terraform.

## AppSync GraphQL API

```hcl
resource "aws_appsync_graphql_api" "main" {
  name                = "${var.prefix}-api"
  authentication_type = "AMAZON_COGNITO_USER_POOLS"

  user_pool_config {
    user_pool_id   = var.cognito_user_pool_id
    aws_region     = var.region
    default_action = "ALLOW"
  }

  additional_authentication_provider {
    authentication_type = "API_KEY"
  }

  additional_authentication_provider {
    authentication_type = "AWS_IAM"
  }

  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logs.arn
    field_log_level          = "ERROR"
    exclude_verbose_content  = false
  }

  xray_enabled = true
  tags         = var.tags
}

resource "aws_appsync_api_key" "public" {
  api_id  = aws_appsync_graphql_api.main.id
  expires = timeadd(timestamp(), "8760h")
}
```

## Schema

```hcl
resource "aws_appsync_graphql_api" "main" {
  schema = <<-GRAPHQL
    type Order {
      orderId: ID!
      customerId: ID!
      status: OrderStatus!
      items: [OrderItem!]!
      totalAmount: Float!
      createdAt: AWSDateTime!
    }

    enum OrderStatus {
      PENDING
      PROCESSING
      SHIPPED
      DELIVERED
      CANCELLED
    }

    type OrderItem {
      productId: ID!
      quantity: Int!
      price: Float!
    }

    type Query {
      getOrder(orderId: ID!): Order
        @aws_cognito_user_pools
      listCustomerOrders(customerId: ID!, limit: Int, nextToken: String): OrderConnection
        @aws_cognito_user_pools
    }

    type Mutation {
      createOrder(input: CreateOrderInput!): Order
        @aws_cognito_user_pools
      updateOrderStatus(orderId: ID!, status: OrderStatus!): Order
        @aws_iam
    }

    type Subscription {
      onOrderUpdated(customerId: ID!): Order
        @aws_subscribe(mutations: ["updateOrderStatus"])
        @aws_cognito_user_pools
    }

    type OrderConnection {
      items: [Order]
      nextToken: String
    }

    input CreateOrderInput {
      customerId: ID!
      items: [OrderItemInput!]!
    }

    input OrderItemInput {
      productId: ID!
      quantity: Int!
      price: Float!
    }
  GRAPHQL
}
```

## DynamoDB Data Source

```hcl
resource "aws_appsync_datasource" "orders" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "OrdersTable"
  service_role_arn = aws_iam_role.appsync_dynamodb.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = var.orders_table_name
    region     = var.region
  }
}

resource "aws_appsync_resolver" "get_order" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Query"
  field       = "getOrder"
  data_source = aws_appsync_datasource.orders.name
  kind        = "UNIT"

  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }

  code = <<-JS
    import { util } from '@aws-appsync/utils'

    export function request(ctx) {
      return {
        operation: 'GetItem',
        key: { orderId: util.dynamodb.toDynamoDB(ctx.args.orderId) }
      }
    }

    export function response(ctx) {
      if (ctx.error) util.error(ctx.error.message, ctx.error.type)
      return ctx.result
    }
  JS
}
```

## Lambda Resolver for Complex Logic

```hcl
resource "aws_appsync_datasource" "create_order" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "CreateOrderFunction"
  service_role_arn = aws_iam_role.appsync_lambda.arn
  type             = "AWS_LAMBDA"

  lambda_config {
    function_arn = aws_lambda_function.create_order.arn
  }
}

resource "aws_appsync_resolver" "create_order" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Mutation"
  field       = "createOrder"
  data_source = aws_appsync_datasource.create_order.name

  request_template  = "{\"version\": \"2018-05-29\", \"operation\": \"Invoke\", \"payload\": $util.toJson($ctx.args)}"
  response_template = "$util.toJson($ctx.result)"
}
```

## Production Checklist

- [ ] Multi-auth: Cognito for users, IAM for service-to-service, API key for public
- [ ] @aws_cognito_user_pools / @aws_iam directives per resolver (field-level auth)
- [ ] Real-time subscriptions with customer-scoped filter (no data leakage)
- [ ] AppSync JS runtime for resolvers (vs VTL — more debuggable)
- [ ] Lambda resolver for mutations with business logic (not direct DDB)
- [ ] CloudWatch logging at ERROR level + X-Ray tracing
- [ ] API key rotation (expires max 365 days; automate with EventBridge)
- [ ] Caching per resolver (reduce DynamoDB reads on hot paths)

AppSync subscriptions are the killer feature for real-time apps — no WebSocket management, no connection state, no pub/sub server. Clients subscribe to mutations and AppSync delivers updates automatically.

## About This Guide

This guide is part of the Citadel Cloud Management content series covering AWS, Azure, GCP, DevSecOps, MCP Servers, and Cloud Careers. Follow our GitHub: https://github.com/kogunlowo123/citadel-cloud-management
