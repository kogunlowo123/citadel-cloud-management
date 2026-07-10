# GCP Cloud Functions Gen2 with Terraform: Serverless Event Processing

**Pillar:** GCP Infrastructure
**SEO Target:** gcp cloud functions gen2 terraform eventarc pub/sub serverless python
**Word Count:** ~1600

Cloud Functions Gen2 runs on Cloud Run infrastructure, which means longer timeouts (60 min), larger instances (32GB RAM), VPC connectivity, and concurrency within a single function instance. This guide deploys a production serverless event processing system using Eventarc, Pub/Sub, and Cloud Functions Gen2 with Terraform.

## Source Bucket and Artifact Registry

```hcl
resource "google_storage_bucket" "functions_source" {
  name                        = "${var.prefix}-functions-source-${var.project_id}"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action { type = "Delete" }
    condition { age = 30 }
  }

  labels = var.labels
}

resource "google_artifact_registry_repository" "functions" {
  repository_id = "${var.prefix}-functions"
  location      = var.region
  project       = var.project_id
  format        = "DOCKER"
  description   = "Container images for Cloud Functions Gen2"

  labels = var.labels
}
```

## Service Account with Least Privilege

```hcl
resource "google_service_account" "functions" {
  account_id   = "${var.prefix}-functions-sa"
  display_name = "Cloud Functions Runtime SA"
  project      = var.project_id
}

resource "google_project_iam_member" "functions_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.functions.email}"
}

resource "google_project_iam_member" "functions_storage_reader" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.functions.email}"
}

resource "google_project_iam_member" "functions_secret_reader" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.functions.email}"
}

resource "google_project_iam_member" "functions_cloudrun_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.functions.email}"
}
```

## Pub/Sub Trigger Function (Gen2)

```hcl
resource "google_cloudfunctions2_function" "event_processor" {
  name        = "${var.prefix}-event-processor"
  location    = var.region
  project     = var.project_id
  description = "Processes events from Pub/Sub and writes to BigQuery"

  build_config {
    runtime     = "python312"
    entry_point = "process_event"

    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.event_processor.name
      }
    }

    environment_variables = {
      GOOGLE_FUNCTION_SOURCE = "main.py"
    }
  }

  service_config {
    min_instance_count             = 0
    max_instance_count             = 100
    max_instance_request_concurrency = 80
    available_memory               = "512Mi"
    available_cpu                  = "1"
    timeout_seconds                = 300
    service_account_email          = google_service_account.functions.email

    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    vpc_connector                  = google_vpc_access_connector.main.id
    vpc_connector_egress_settings  = "PRIVATE_RANGES_ONLY"

    environment_variables = {
      PROJECT_ID = var.project_id
      DATASET_ID = var.bq_dataset_id
      TABLE_ID   = var.bq_table_id
    }

    secret_environment_variables {
      key        = "DATABASE_URL"
      project_id = var.project_id
      secret     = google_secret_manager_secret.db_url.secret_id
      version    = "latest"
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.events.id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.functions.email
  }

  labels = var.labels
}
```

## HTTP Function with Authentication

```hcl
resource "google_cloudfunctions2_function" "api_handler" {
  name        = "${var.prefix}-api-handler"
  location    = var.region
  project     = var.project_id
  description = "HTTP handler for internal API endpoints"

  build_config {
    runtime     = "python312"
    entry_point = "handle_request"
    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.api_handler.name
      }
    }
  }

  service_config {
    min_instance_count               = 1
    max_instance_count               = 50
    max_instance_request_concurrency = 10
    available_memory                 = "256Mi"
    available_cpu                    = "0.5"
    timeout_seconds                  = 60
    service_account_email            = google_service_account.functions.email
    ingress_settings                 = "ALLOW_INTERNAL_AND_GCLB"
  }

  labels = var.labels
}

resource "google_cloud_run_service_iam_binding" "api_invokers" {
  location = var.region
  project  = var.project_id
  service  = google_cloudfunctions2_function.api_handler.name
  role     = "roles/run.invoker"
  members  = ["serviceAccount:${var.api_gateway_sa_email}"]
}
```

## Eventarc GCS Trigger

```hcl
resource "google_cloudfunctions2_function" "gcs_processor" {
  name        = "${var.prefix}-gcs-processor"
  location    = var.region
  project     = var.project_id
  description = "Processes files uploaded to GCS"

  build_config {
    runtime     = "python312"
    entry_point = "process_file"
    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.gcs_processor.name
      }
    }
  }

  service_config {
    min_instance_count = 0
    max_instance_count = 20
    available_memory   = "1Gi"
    available_cpu      = "1"
    timeout_seconds    = 540
    service_account_email = google_service_account.functions.email
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.storage.object.v1.finalized"
    retry_policy          = "RETRY_POLICY_DO_NOT_RETRY"
    service_account_email = google_service_account.functions.email

    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.uploads.name
    }
  }

  labels = var.labels
}
```

## Python Function Code

```python
# main.py — Pub/Sub event processor
import base64
import json
import os
from google.cloud import bigquery
import functions_framework

bq = bigquery.Client()

@functions_framework.cloud_event
def process_event(cloud_event):
    data = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8")
    event = json.loads(data)
    
    table_id = f"{os.environ['PROJECT_ID']}.{os.environ['DATASET_ID']}.{os.environ['TABLE_ID']}"
    
    errors = bq.insert_rows_json(table_id, [event])
    if errors:
        raise RuntimeError(f"BigQuery insert errors: {errors}")
    
    print(f"Processed event: {event.get('event_id')}")
```

## Production Checklist

- [ ] Gen2 with concurrency (max 80 per instance — eliminates cold start overhead)
- [ ] min_instance_count=0 for event processors, min=1 for latency-sensitive HTTP
- [ ] VPC connector for private resource access (CloudSQL, Redis)
- [ ] Secrets via Secret Manager (not environment variables)
- [ ] ALLOW_INTERNAL_ONLY ingress for Pub/Sub triggered functions
- [ ] Eventarc for GCS triggers (not legacy GCS trigger — deprecated in Gen2)
- [ ] Retry policy: RETRY_POLICY_RETRY for idempotent handlers, DO_NOT_RETRY otherwise
- [ ] Artifact Registry for container caching (speeds cold starts)
- [ ] Cloud Monitoring alerting on function error rate and latency

Cloud Functions Gen2's concurrency feature is the game-changer — a single warm instance handles 80 concurrent requests instead of 1, which reduces cold starts by 80× at steady-state traffic.
