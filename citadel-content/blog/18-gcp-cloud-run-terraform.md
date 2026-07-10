# GCP Cloud Run with Terraform: Serverless Containers at Scale

**Pillar:** GCP Infrastructure
**SEO Target:** gcp cloud run terraform serverless
**Word Count:** ~1700

Google Cloud Run is the fully managed serverless platform for running containers. No Kubernetes to manage — you bring a container, Cloud Run handles scaling from zero to thousands of instances. This guide covers deploying Cloud Run services with Terraform including VPC connectivity, Secret Manager integration, and Cloud Armor protection.

## Why Cloud Run

Cloud Run charges only for actual compute time (100ms billing granularity), scales to zero when idle, and supports any language or framework in a container. For microservices, APIs, and event-driven workloads, it often beats running a full GKE cluster on total cost.

## Basic Service

```hcl
resource "google_cloud_run_v2_service" "main" {
  name     = "${var.name}-${var.environment}"
  location = var.region
  project  = var.project_id

  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.app.email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.container_image

      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      ports {
        container_port = var.container_port
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_url.secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/health"
          port = var.container_port
        }
        initial_delay_seconds = 5
        period_seconds        = 3
        failure_threshold     = 10
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = var.container_port
        }
        period_seconds    = 15
        failure_threshold = 3
      }
    }

    vpc_access {
      connector = google_vpc_access_connector.main.id
      egress    = "PRIVATE_RANGES_ONLY"
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}
```

## VPC Access Connector

```hcl
resource "google_vpc_access_connector" "main" {
  name          = "${var.name}-connector"
  region        = var.region
  project       = var.project_id
  network       = var.vpc_name
  ip_cidr_range = var.connector_cidr

  min_instances = 2
  max_instances = 10
  machine_type  = "e2-standard-4"
}
```

## Service Account and IAM

```hcl
resource "google_service_account" "app" {
  account_id   = "${var.name}-sa"
  display_name = "${var.name} Cloud Run SA"
  project      = var.project_id
}

# Access Secret Manager
resource "google_secret_manager_secret_iam_member" "app_db_url" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

# Access Cloud SQL
resource "google_project_iam_member" "app_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Allow authenticated users to invoke the service
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.main.name
  role     = "roles/run.invoker"
  member   = "allAuthenticatedUsers"
}
```

## Secret Manager Integration

```hcl
resource "google_secret_manager_secret" "db_url" {
  project   = var.project_id
  secret_id = "${var.name}-db-url"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_url" {
  secret      = google_secret_manager_secret.db_url.id
  secret_data = var.database_url

  lifecycle {
    ignore_changes = [secret_data]
  }
}
```

## Load Balancer with Cloud Armor

```hcl
# Serverless Network Endpoint Group
resource "google_compute_region_network_endpoint_group" "cloudrun" {
  name                  = "${var.name}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  project               = var.project_id

  cloud_run {
    service = google_cloud_run_v2_service.main.name
  }
}

resource "google_compute_backend_service" "cloudrun" {
  name    = "${var.name}-backend"
  project = var.project_id

  protocol    = "HTTPS"
  timeout_sec = 30

  backend {
    group = google_compute_region_network_endpoint_group.cloudrun.id
  }

  security_policy = google_compute_security_policy.main.id

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_security_policy" "main" {
  name    = "${var.name}-armor"
  project = var.project_id

  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
    description = "Block XSS attacks"
  }

  rule {
    action   = "deny(403)"
    priority = 1001
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
    description = "Block SQL injection"
  }

  rule {
    action   = "throttle"
    priority = 2000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
    }
    description = "Rate limit: 100 req/min per IP"
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }
}
```

## Custom Domain and SSL

```hcl
resource "google_compute_managed_ssl_certificate" "main" {
  name    = "${var.name}-cert"
  project = var.project_id

  managed {
    domains = [var.domain_name]
  }
}

resource "google_compute_url_map" "main" {
  name            = "${var.name}-url-map"
  project         = var.project_id
  default_service = google_compute_backend_service.cloudrun.id
}

resource "google_compute_target_https_proxy" "main" {
  name             = "${var.name}-https-proxy"
  project          = var.project_id
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main.id]
}

resource "google_compute_global_forwarding_rule" "https" {
  name       = "${var.name}-https"
  project    = var.project_id
  target     = google_compute_target_https_proxy.main.id
  port_range = "443"
  ip_address = google_compute_global_address.main.address
}
```

## Variables

```hcl
variable "name" { type = string }
variable "environment" { type = string }
variable "project_id" { type = string }
variable "region" { type = string; default = "us-central1" }
variable "container_image" { type = string }
variable "container_port" { type = number; default = 8080 }
variable "min_instances" { type = number; default = 0 }
variable "max_instances" { type = number; default = 100 }
variable "cpu_limit" { type = string; default = "1" }
variable "memory_limit" { type = string; default = "512Mi" }
variable "vpc_name" { type = string }
variable "connector_cidr" { type = string }
variable "database_url" { type = string; sensitive = true }
variable "domain_name" { type = string }
```

## Outputs

```hcl
output "service_url" {
  value = google_cloud_run_v2_service.main.uri
}

output "service_name" {
  value = google_cloud_run_v2_service.main.name
}

output "load_balancer_ip" {
  value = google_compute_global_address.main.address
}
```

## Production Checklist

- [ ] `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` — no direct public access
- [ ] VPC connector for private database/Redis access
- [ ] Workload Identity (service account) — no keys
- [ ] Secret Manager for all credentials
- [ ] Cloud Armor with OWASP rules and rate limiting
- [ ] Managed SSL certificate on load balancer
- [ ] CPU idle = true for cost savings
- [ ] Startup CPU boost for faster cold starts
- [ ] Health probes configured (startup + liveness)
- [ ] Min instances > 0 for latency-sensitive services

Cloud Run backed by Cloud Armor and a Global Load Balancer gives you a production-grade serverless deployment with enterprise security controls — without the overhead of cluster management.
