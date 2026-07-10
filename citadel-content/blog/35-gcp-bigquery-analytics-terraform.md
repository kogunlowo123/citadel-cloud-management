# GCP BigQuery Analytics Platform with Terraform: Data Warehouse in Production

**Pillar:** GCP Infrastructure
**SEO Target:** gcp bigquery terraform data warehouse analytics dbt looker
**Word Count:** ~1600

BigQuery is Google Cloud's serverless data warehouse. Petabyte-scale queries in seconds, no infrastructure to manage, pay-per-query pricing. This guide builds a production analytics platform: datasets, row-level security, scheduled queries, and Pub/Sub streaming ingest.

## Datasets with Access Controls

```hcl
resource "google_bigquery_dataset" "raw" {
  dataset_id            = "${replace(var.prefix, "-", "_")}_raw"
  location              = var.region
  project               = var.project_id
  description           = "Raw ingestion layer — unmodified source data"
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

resource "google_bigquery_dataset" "transformed" {
  dataset_id  = "${replace(var.prefix, "-", "_")}_transformed"
  location    = var.region
  project     = var.project_id
  description = "Transformed layer — dbt models, production-ready"

  access {
    role          = "OWNER"
    user_by_email = var.dbt_sa_email
  }

  access {
    role           = "READER"
    special_group  = "projectReaders"
  }

  labels = var.labels
}

resource "google_bigquery_dataset" "marts" {
  dataset_id  = "${replace(var.prefix, "-", "_")}_marts"
  location    = var.region
  project     = var.project_id
  description = "Data marts — business-facing aggregated views"

  access {
    role          = "OWNER"
    user_by_email = var.dbt_sa_email
  }

  access {
    role          = "READER"
    iam_member    = "group:${var.analysts_group_email}"
  }

  labels = var.labels
}
```

## Table with Row-Level Security

```hcl
resource "google_bigquery_table" "events" {
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "events"
  project             = var.project_id
  deletion_protection = var.environment == "prod"

  schema = jsonencode([
    { name = "event_id",      type = "STRING",    mode = "REQUIRED" },
    { name = "user_id",       type = "STRING",    mode = "REQUIRED" },
    { name = "event_type",    type = "STRING",    mode = "REQUIRED" },
    { name = "tenant_id",     type = "STRING",    mode = "REQUIRED" },
    { name = "properties",    type = "JSON",      mode = "NULLABLE" },
    { name = "created_at",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "ingested_at",   type = "TIMESTAMP", mode = "REQUIRED" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "created_at"
    expiration_ms = null
  }

  clustering = ["tenant_id", "event_type", "user_id"]

  labels = var.labels
}

resource "google_bigquery_table_iam_binding" "events_readers" {
  project  = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  table_id   = google_bigquery_table.events.table_id
  role       = "roles/bigquery.dataViewer"

  members = [
    "serviceAccount:${var.dbt_sa_email}",
    "group:${var.data_team_group}"
  ]
}

resource "google_bigquery_row_access_policy" "tenant_filter" {
  dataset_id   = google_bigquery_dataset.raw.dataset_id
  table_id     = google_bigquery_table.events.table_id
  policy_id    = "tenant-isolation"
  project      = var.project_id

  filter_predicate = "tenant_id = SESSION_USER()"

  grantees = ["group:${var.analysts_group_email}"]
}
```

## Pub/Sub Streaming Ingestion

```hcl
resource "google_pubsub_topic" "events" {
  name    = "${var.prefix}-events"
  project = var.project_id

  message_retention_duration = "86600s"

  schema_settings {
    schema   = google_pubsub_schema.event.id
    encoding = "JSON"
  }

  labels = var.labels
}

resource "google_pubsub_schema" "event" {
  name       = "${var.prefix}-event-schema"
  type       = "AVRO"
  project    = var.project_id
  definition = jsonencode({
    type = "record"
    name = "Event"
    fields = [
      { name = "event_id",   type = "string" },
      { name = "user_id",    type = "string" },
      { name = "event_type", type = "string" },
      { name = "tenant_id",  type = "string" },
      { name = "created_at", type = "long", logicalType = "timestamp-millis" }
    ]
  })
}

resource "google_pubsub_subscription" "bigquery_sink" {
  name    = "${var.prefix}-events-bq-sink"
  topic   = google_pubsub_topic.events.name
  project = var.project_id

  bigquery_config {
    table              = "${var.project_id}.${google_bigquery_dataset.raw.dataset_id}.${google_bigquery_table.events.table_id}"
    use_topic_schema   = true
    write_metadata     = false
    drop_unknown_fields = true
  }

  ack_deadline_seconds    = 60
  message_retention_duration = "86600s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
}
```

## Scheduled Query (Materialized Aggregation)

```hcl
resource "google_bigquery_data_transfer_config" "daily_summary" {
  display_name           = "Daily Event Summary"
  location               = var.region
  project                = var.project_id
  data_source_id         = "scheduled_query"
  schedule               = "every 24 hours"
  destination_dataset_id = google_bigquery_dataset.transformed.dataset_id

  params = {
    query = <<-SQL
      INSERT INTO `${var.project_id}.${replace(var.prefix, "-", "_")}_transformed.daily_event_summary`
      SELECT
        DATE(created_at)         AS event_date,
        tenant_id,
        event_type,
        COUNT(*)                 AS event_count,
        COUNT(DISTINCT user_id)  AS unique_users,
        CURRENT_TIMESTAMP()      AS updated_at
      FROM `${var.project_id}.${replace(var.prefix, "-", "_")}_raw.events`
      WHERE DATE(created_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
      GROUP BY 1, 2, 3
    SQL
    destination_table_name_template = "daily_event_summary"
    write_disposition               = "WRITE_APPEND"
    partitioning_field              = "event_date"
  }

  service_account_name = var.bq_transfer_sa_email
}
```

## Budget Alert

```hcl
resource "google_billing_budget" "bigquery" {
  billing_account = var.billing_account_id
  display_name    = "${var.prefix}-bigquery-budget"

  budget_filter {
    projects = ["projects/${var.project_number}"]
    services = ["services/95FF-2EF5-5EA1"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_bq_budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.9
    spend_basis       = "CURRENT_SPEND"
  }
}
```

## Production Checklist

- [ ] Three-layer dataset structure: raw → transformed → marts
- [ ] Row-level security with tenant_id filter (multi-tenant isolation)
- [ ] Partition on time column + clustering on high-cardinality filter columns
- [ ] Pub/Sub → BigQuery direct sink with Avro schema validation
- [ ] Scheduled query for daily aggregations (avoid on-demand scan costs)
- [ ] Budget alerts at 50% and 90% of monthly BigQuery budget
- [ ] IAM: dbt SA gets raw read + transformed write; analysts get marts read only
- [ ] deletion_protection enabled on production tables
- [ ] Authorized views for cross-dataset access without credential sharing

BigQuery's columnar storage with partition pruning and clustering reduces scan costs dramatically — on a 10TB table, the right partition/cluster setup cuts query cost by 90%+ compared to full table scans.
