# AWS Athena with Terraform: SQL Analytics on S3

**Pillar:** AWS Infrastructure
**SEO Target:** aws athena terraform sql s3 data lake analytics workgroup iceberg
**Word Count:** ~1400

Athena queries S3 data directly with standard SQL. No ETL, no database to maintain, pay per query. This guide deploys production Athena with workgroups, result encryption, and Apache Iceberg tables.

## Workgroup

```hcl
resource "aws_athena_workgroup" "main" {
  name        = "${var.prefix}-main"
  description = "Production Athena workgroup with cost controls"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 10737418240

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"
      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key           = aws_kms_key.athena.arn
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = var.tags
}
```

## Iceberg Table

```hcl
resource "aws_athena_named_query" "create_iceberg_table" {
  name      = "create-events-iceberg"
  workgroup = aws_athena_workgroup.main.id
  database  = aws_glue_catalog_database.raw.name

  query = <<-SQL
    CREATE TABLE IF NOT EXISTS events_iceberg (
      event_id     STRING,
      user_id      STRING,
      event_type   STRING,
      tenant_id    STRING,
      properties   MAP<STRING, STRING>,
      created_at   TIMESTAMP
    )
    PARTITIONED BY (tenant_id, event_date DATE)
    LOCATION 's3://${var.data_bucket}/iceberg/events/'
    TBLPROPERTIES (
      'table_type'             = 'ICEBERG',
      'format'                 = 'PARQUET',
      'write_compression'      = 'SNAPPY',
      'optimize_rewrite_delete_file_threshold' = '10'
    )
  SQL
}
```

## Query Cost Alert

```hcl
resource "aws_cloudwatch_metric_alarm" "athena_data_scanned" {
  alarm_name          = "${var.prefix}-athena-data-scanned"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DataScannedInBytes"
  namespace           = "AWS/Athena"
  period              = 86400
  statistic           = "Sum"
  threshold           = 107374182400
  alarm_description   = "Athena scanned > 100GB today"
  dimensions          = { WorkGroup = aws_athena_workgroup.main.name }
  alarm_actions       = [var.alert_sns_arn]
}
```

## Production Checklist
- [ ] bytes_scanned_cutoff_per_query (10GB limit prevents runaway queries)
- [ ] Results encrypted with KMS in dedicated S3 bucket
- [ ] Athena Engine v3 (fastest, best Iceberg support)
- [ ] Iceberg table format: ACID transactions, schema evolution, time travel
- [ ] Partition projection on time-based partitions (eliminates Glue metadata calls)
- [ ] Parquet format with Snappy compression (10× smaller than CSV)
- [ ] CloudWatch alarm on total daily data scanned > 100GB