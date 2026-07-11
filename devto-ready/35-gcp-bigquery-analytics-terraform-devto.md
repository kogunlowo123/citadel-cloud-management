---
title: "GCP BigQuery Analytics Platform with Terraform: Data Warehouse in Production"
published: true
description: "Build a production BigQuery analytics platform with Terraform: datasets with row-level security, scheduled queries, Pub/Sub streaming ingest, and dbt integration. Full Terraform code."
tags: gcp, terraform, dataengineering, analytics
series: "Citadel Cloud Management: 100 Free Terraform Guides"
canonical_url: https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/35-gcp-bigquery-analytics-terraform.md
cover_image: https://kogunlowo123.github.io/citadel-cloud-management/assets/images/og-default.png
---

> **This is part of the [Citadel Cloud Management](https://github.com/kogunlowo123/citadel-cloud-management) free Terraform guide library — 100+ production-ready guides, MIT licensed, no paywall.**

BigQuery is Google Cloud's serverless data warehouse — petabyte-scale queries in seconds, no infrastructure to manage, pay-per-query pricing. This guide builds a production analytics platform with Terraform: layered datasets, row-level security, Pub/Sub streaming ingest, and scheduled queries.

## Dataset Architecture: Medallion Layers

```
Pub/Sub (streaming) ──┐
S3/GCS transfer   ──┤
Batch CSV upload  ──┘
        ↓
    raw dataset      (unmodified source data)
        ↓
    staging dataset  (dbt transformations)
        ↓
    analytics dataset (business-ready models)
        ↓
    Looker / Data Studio
```

## Datasets with Access Controls

```hcl
resource "google_bigquery_dataset" "raw" {
  dataset_id  = "${replace(var.prefix, "-", "_")}_raw"
  location    = var.region
  project     = var.project_id
  description = "Raw ingestion layer — unmodified source data"
  default_table_expiration_ms = null

  access {
    role          = "OWNER"
    user_by_email = var.data_engineering_sa_email
  }

  access {
    role          = "READER"
    user_by_email = var.dbt_sa_email
  }

  labels = var.labels
}

resource "google_bigquery_dataset" "analytics" {
  dataset_id  = "${replace(var.prefix, "-", "_")}_analytics"
  location    = var.region
  project     = var.project_id
  description = "Business-ready analytics models"

  access {
    role          = "READER"
    special_group = "projectViewers"
  }

  access {
    role          = "WRITER"
    user_by_email = var.dbt_sa_email
  }

  labels = var.labels
}
```

## Row-Level Security (Column-Level Too)

```hcl
# Row-level security: analysts only see their region's data
resource "google_bigquery_dataset_iam_member" "analytics_viewer" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${var.analyst_sa_email}"
  project    = var.project_id
}

# Row access policy: filter by region
resource "google_bigquery_table_iam_policy" "orders_rls" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "orders"
  project    = var.project_id

  policy_data = data.google_iam_policy.orders_policy.policy_data
}

resource "google_bigquery_row_access_policy" "region_filter" {
  dataset_id  = google_bigquery_dataset.analytics.dataset_id
  table_id    = "orders"
  policy_id   = "region-filter"
  project     = var.project_id

  filter_predicate = "region = SESSION_USER()"  # Matches user's email prefix

  grantees = [
    "serviceAccount:${var.analyst_sa_email}"
  ]
}
```

## Pub/Sub Streaming Ingest

```hcl
resource "google_pubsub_topic" "events" {
  name    = "${var.prefix}-events"
  project = var.project_id

  message_retention_duration = "86400s"  # 24h

  schema_settings {
    schema   = google_pubsub_schema.events.id
    encoding = "JSON"
  }

  labels = var.labels
}

resource "google_pubsub_schema" "events" {
  name       = "${var.prefix}-events-schema"
  type       = "AVRO"
  project    = var.project_id
  definition = jsonencode({
    type = "record"
    name = "Event"
    fields = [
      { name = "event_id",   type = "string" },
      { name = "event_type", type = "string" },
      { name = "user_id",    type = "string" },
      { name = "timestamp",  type = "long",   logicalType = "timestamp-micros" },
      { name = "properties", type = "string" }
    ]
  })
}

# BigQuery subscription — direct Pub/Sub → BigQuery without Dataflow
resource "google_pubsub_subscription" "bq_events" {
  name    = "${var.prefix}-bq-events"
  topic   = google_pubsub_topic.events.id
  project = var.project_id

  bigquery_config {
    table            = "${var.project_id}.${google_bigquery_dataset.raw.dataset_id}.events"
    use_topic_schema = true
    write_metadata   = true
  }
}
```

## Scheduled Queries (Materialized Aggregates)

```hcl
resource "google_bigquery_data_transfer_config" "daily_agg" {
  display_name           = "daily-user-aggregates"
  location               = var.region
  data_source_id         = "scheduled_query"
  project                = var.project_id
  schedule               = "every 24 hours"
  destination_dataset_id = google_bigquery_dataset.analytics.dataset_id

  params = {
    query = <<-SQL
      SELECT
        DATE(timestamp) AS date,
        user_id,
        COUNT(*) AS event_count,
        COUNTIF(event_type = 'purchase') AS purchase_count,
        SUM(SAFE_CAST(JSON_VALUE(properties, '$.revenue') AS FLOAT64)) AS revenue
      FROM `${var.project_id}.${google_bigquery_dataset.raw.dataset_id}.events`
      WHERE DATE(timestamp) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
      GROUP BY 1, 2
    SQL
    destination_table_name_template = "user_daily_agg_{run_date}"
    write_disposition               = "WRITE_TRUNCATE"
    partitioning_field              = "date"
  }

  service_account_name = google_service_account.bq_scheduler.email
}
```

## Cost Controls

```hcl
# Project-level cost control: alert at $500
resource "google_billing_budget" "bigquery" {
  billing_account = var.billing_account_id
  display_name    = "${var.prefix}-bigquery-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    services = ["services/95FF-2EF5-5EA1"]  # BigQuery service ID
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "500"
    }
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    pubsub_topic = google_pubsub_topic.budget_alerts.id
  }
}
```

## Production Checklist

- [ ] Medallion layers: raw → staging → analytics datasets
- [ ] Row-level security policies per dataset (not just IAM)
- [ ] Pub/Sub schema with Avro validation before ingest
- [ ] BigQuery subscription (direct Pub/Sub → BQ, no Dataflow needed)
- [ ] Scheduled queries with `WRITE_TRUNCATE` + date partitioning
- [ ] Column-level encryption for PII fields
- [ ] Billing budget alert at 80% threshold
- [ ] Dataset expiration for raw layer (90-day TTL)
- [ ] Reservation slots for predictable query cost in production

## Full Code

Complete guide with dbt service account setup, Looker Studio integration, column-level encryption, and slot reservations:

👉 [github.com/kogunlowo123/citadel-cloud-management — Article 35](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/35-gcp-bigquery-analytics-terraform.md)

---

*Part of 100 free production Terraform guides covering AWS, Azure, GCP, Kubernetes, DevSecOps, AI/ML, and Cloud Careers. MIT licensed. [Browse the full library →](https://github.com/kogunlowo123/citadel-cloud-management)*
