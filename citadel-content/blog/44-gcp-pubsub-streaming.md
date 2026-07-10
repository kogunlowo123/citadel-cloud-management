# GCP Pub/Sub Streaming Architecture with Terraform

**Pillar:** GCP Infrastructure
**SEO Target:** gcp pub/sub terraform streaming architecture dataflow pipeline
**Word Count:** ~1500

GCP Pub/Sub is a fully managed, real-time messaging service for streaming analytics and event-driven systems. With Dataflow as the processing engine, you get exactly-once semantics, auto-scaling, and a rich windowing API. This guide builds a streaming analytics pipeline with Terraform.

## Pub/Sub Topics and Subscriptions

```hcl
resource "google_pubsub_topic" "clickstream" {
  name    = "${var.prefix}-clickstream"
  project = var.project_id

  message_retention_duration = "86600s"

  schema_settings {
    schema   = google_pubsub_schema.clickevent.id
    encoding = "JSON"
  }

  labels = var.labels
}

resource "google_pubsub_subscription" "dataflow_sink" {
  name    = "${var.prefix}-clickstream-dataflow"
  topic   = google_pubsub_topic.clickstream.name
  project = var.project_id

  ack_deadline_seconds       = 60
  retain_acked_messages      = false
  message_retention_duration = "600s"

  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.clickstream_dlq.id
    max_delivery_attempts = 5
  }
}

resource "google_pubsub_topic" "clickstream_dlq" {
  name    = "${var.prefix}-clickstream-dlq"
  project = var.project_id
  labels  = var.labels
}
```

## Dataflow Streaming Job

```hcl
resource "google_dataflow_flex_template_job" "streaming" {
  provider          = google-beta
  name              = "${var.prefix}-streaming-pipeline"
  region            = var.region
  project           = var.project_id
  container_spec_gcs_path = "gs://dataflow-templates-${var.region}/latest/flex/PubSub_to_BigQuery_Flex"

  parameters = {
    inputTopic           = google_pubsub_topic.clickstream.id
    outputTableSpec      = "${var.project_id}:${var.bq_dataset}.${var.bq_table}"
    outputDeadletterTable = "${var.project_id}:${var.bq_dataset}.clickstream_dlq"
    useStorageWriteApi   = "true"
  }

  on_delete = "cancel"

  additional_experiments = [
    "enable_recommendations",
    "use_runner_v2"
  ]

  labels = var.labels
}
```

## Cloud Monitoring for Pub/Sub

```hcl
resource "google_monitoring_alert_policy" "pubsub_backlog" {
  display_name = "${var.prefix} Pub/Sub subscription backlog high"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Undelivered message count > 1000"
    condition_threshold {
      filter     = "resource.type=\"pubsub_subscription\" AND metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND resource.label.subscription_id=\"${google_pubsub_subscription.dataflow_sink.name}\""
      comparison = "COMPARISON_GT"
      threshold_value = 1000
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }
}
```

## Production Checklist

- [ ] Schema validation on topic (rejects malformed messages at publish time)
- [ ] Dead-letter topic with max 5 delivery attempts
- [ ] Dataflow Flex Template for managed streaming processing
- [ ] Storage Write API enabled for BigQuery sink (higher throughput, lower cost)
- [ ] Cloud Monitoring alert on subscription backlog > 1000
- [ ] Separate subscriptions per consumer (each gets independent offset)
- [ ] Message retention: 86600s on topic (1 day) for replay capability
- [ ] IAM: publisher SA gets pubsub.publisher, subscriber SA gets pubsub.subscriber only

Pub/Sub's infinite scalability combined with Dataflow's exactly-once streaming gives you a pipeline that handles both 100 events/second and 100,000 events/second with the same code.

## About This Guide

This guide is part of the Citadel Cloud Management content series covering AWS, Azure, GCP, DevSecOps, MCP Servers, and Cloud Careers. Follow our GitHub: https://github.com/kogunlowo123/citadel-cloud-management
