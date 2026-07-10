# Azure Container Apps with Terraform: Serverless Microservices

**Pillar:** Azure Infrastructure
**SEO Target:** azure container apps terraform microservices serverless dapr
**Word Count:** ~1600

Azure Container Apps is Microsoft's fully managed serverless container platform built on Kubernetes and KEDA. It handles scaling, networking, and service mesh without cluster management. This guide deploys a production microservices architecture with Dapr integration using Terraform.

## Container Apps Environment

```hcl
resource "azurerm_container_app_environment" "main" {
  name                       = "${var.prefix}-cae"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  infrastructure_subnet_id = azurerm_subnet.container_apps.id
  internal_load_balancer_enabled = true

  dapr_application_insights_connection_string = azurerm_application_insights.main.connection_string

  tags = var.tags
}

resource "azurerm_container_app_environment_dapr_component" "redis" {
  name                         = "statestore"
  container_app_environment_id = azurerm_container_app_environment.main.id
  component_type               = "state.redis"
  version                      = "v1"

  metadata {
    name  = "redisHost"
    value = "${azurerm_redis_cache.main.hostname}:${azurerm_redis_cache.main.ssl_port}"
  }

  metadata {
    name        = "redisPassword"
    secret_name = "redis-password"
  }

  secret {
    name  = "redis-password"
    value = azurerm_redis_cache.main.primary_access_key
  }
}
```

## API Gateway Container App

```hcl
resource "azurerm_container_app" "api" {
  name                         = "${var.prefix}-api"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Multiple"

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 8080

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  dapr {
    app_id       = "api"
    app_port     = 8080
    app_protocol = "http"
  }

  template {
    min_replicas = 1
    max_replicas = 20

    http_scale_rule {
      name                = "http-scaler"
      concurrent_requests = "100"
    }

    container {
      name   = "api"
      image  = "${azurerm_container_registry.main.login_server}/${var.api_image}:${var.api_version}"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = var.environment
      }

      env {
        name        = "DATABASE_CONNECTION_STRING"
        secret_name = "db-connection"
      }

      liveness_probe {
        port      = 8080
        path      = "/health/live"
        transport = "HTTP"
        initial_delay  = 30
        period_seconds = 10
        failure_count_threshold = 3
      }

      readiness_probe {
        port      = 8080
        path      = "/health/ready"
        transport = "HTTP"
        initial_delay  = 10
        period_seconds = 5
        success_count_threshold = 1
      }
    }
  }

  secret {
    name  = "db-connection"
    value = azurerm_key_vault_secret.db_connection.value
  }

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.api.id]
  }

  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.api.id
  }

  tags = var.tags
}
```

## Background Worker with KEDA Scaling

```hcl
resource "azurerm_container_app" "worker" {
  name                         = "${var.prefix}-worker"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  template {
    min_replicas = 0
    max_replicas = 10

    custom_scale_rule {
      name             = "servicebus-scaler"
      custom_rule_type = "azure-servicebus"
      metadata = {
        queueName   = azurerm_servicebus_queue.work.name
        namespace   = azurerm_servicebus_namespace.main.name
        messageCount = "5"
      }
      authentication {
        secret_ref        = "servicebus-connection"
        trigger_parameter = "connection"
      }
    }

    container {
      name   = "worker"
      image  = "${azurerm_container_registry.main.login_server}/${var.worker_image}:${var.worker_version}"
      cpu    = 1.0
      memory = "2Gi"

      env {
        name        = "SERVICEBUS_CONNECTION"
        secret_name = "servicebus-connection"
      }

      env {
        name  = "DAPR_APP_ID"
        value = "worker"
      }
    }
  }

  dapr {
    app_id   = "worker"
    app_port = 3000
  }

  secret {
    name  = "servicebus-connection"
    value = azurerm_servicebus_namespace_authorization_rule.worker.primary_connection_string
  }

  tags = var.tags
}
```

## Azure Container Registry

```hcl
resource "azurerm_container_registry" "main" {
  name                = "${replace(var.prefix, "-", "")}acr"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "Premium"

  admin_enabled                 = false
  public_network_access_enabled = false
  zone_redundancy_enabled       = true

  network_rule_set {
    default_action = "Deny"

    virtual_network {
      action    = "Allow"
      subnet_id = azurerm_subnet.container_apps.id
    }
  }

  georeplications {
    location                = var.dr_location
    zone_redundancy_enabled = true
    tags                    = var.tags
  }

  retention_policy {
    days    = 30
    enabled = true
  }

  trust_policy {
    enabled = true
  }

  tags = var.tags
}
```

## Service Bus for Async Communication

```hcl
resource "azurerm_servicebus_namespace" "main" {
  name                = "${var.prefix}-sb"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Premium"
  capacity            = 1

  public_network_access_enabled = false
  minimum_tls_version           = "1.2"

  tags = var.tags
}

resource "azurerm_servicebus_queue" "work" {
  name         = "work-items"
  namespace_id = azurerm_servicebus_namespace.main.id

  max_delivery_count          = 10
  dead_lettering_on_message_expiration = true
  message_retention_in_days   = 3
  requires_duplicate_detection = true

  max_message_size_in_kilobytes = 256
  max_size_in_megabytes         = 1024
}
```

## Production Checklist

- [ ] Container Apps Environment in VNet with internal load balancer
- [ ] Dapr enabled for service-to-service calls and state management
- [ ] Redis as Dapr state store with TLS
- [ ] Multiple revision mode on public-facing apps (for blue-green deploys)
- [ ] HTTP-based scaling on API (100 concurrent requests threshold)
- [ ] KEDA scaling on worker (0 replicas when queue empty — saves cost)
- [ ] ACR Premium with content trust + geo-replication + private endpoint
- [ ] Managed identity for ACR pull (no registry credentials in apps)
- [ ] Health probes: liveness and readiness on all containers

Container Apps with Dapr abstracts away the service mesh complexity while giving you event-driven scaling down to zero — ideal for microservice architectures that need per-service scaling without full Kubernetes overhead.
