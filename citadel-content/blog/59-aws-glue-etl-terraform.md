# AWS Glue ETL with Terraform: Serverless Data Engineering

**Pillar:** AWS Infrastructure
**SEO Target:** aws glue etl terraform data catalog spark serverless pipeline
**Word Count:** ~1400

AWS Glue provides serverless ETL with Spark-based transforms, Data Catalog, and crawlers. No infrastructure to manage — define your job, Glue allocates compute. This guide deploys production Glue ETL pipelines with Terraform.

## Glue Database and Crawler

```hcl
resource "aws_glue_catalog_database" "raw" {
  name        = "${replace(var.prefix, "-", "_")}_raw"
  description = "Raw data landing zone"
}

resource "aws_glue_crawler" "s3_raw" {
  name          = "${var.prefix}-raw-crawler"
  role          = aws_iam_role.glue.arn
  database_name = aws_glue_catalog_database.raw.name
  schedule      = "cron(0 2 * * ? *)"

  s3_target {
    path = "s3://${var.raw_bucket}/data/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  tags = var.tags
}
```

## Glue ETL Job

```hcl
resource "aws_glue_job" "transform" {
  name              = "${var.prefix}-transform"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.environment == "prod" ? 10 : 2
  max_retries       = 1
  timeout           = 60

  command {
    script_location = "s3://${var.scripts_bucket}/glue/transform.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"              = "python"
    "--job-bookmark-option"       = "job-bookmark-enable"
    "--enable-metrics"            = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"           = "true"
    "--spark-event-logs-path"     = "s3://${var.logs_bucket}/spark-events/"
    "--TempDir"                   = "s3://${var.temp_bucket}/glue-temp/"
    "--SOURCE_DATABASE"           = aws_glue_catalog_database.raw.name
    "--TARGET_BUCKET"             = var.processed_bucket
  }

  tags = var.tags
}
```

## Glue Workflow

```hcl
resource "aws_glue_workflow" "daily_pipeline" {
  name        = "${var.prefix}-daily-pipeline"
  description = "Daily ETL: crawl raw → transform → load to Redshift"
  tags        = var.tags
}

resource "aws_glue_trigger" "start_crawler" {
  name          = "${var.prefix}-start-crawler"
  type          = "SCHEDULED"
  schedule      = "cron(0 1 * * ? *)"
  workflow_name = aws_glue_workflow.daily_pipeline.name
  actions { crawler_name = aws_glue_crawler.s3_raw.name }
}

resource "aws_glue_trigger" "start_transform" {
  name          = "${var.prefix}-start-transform"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.daily_pipeline.name

  predicate {
    logical = "AND"
    conditions {
      crawler_name = aws_glue_crawler.s3_raw.name
      crawl_state  = "SUCCEEDED"
    }
  }
  actions { job_name = aws_glue_job.transform.name }
}
```

## Production Checklist
- [ ] Job bookmarks enabled (tracks processed records — enables incremental loads)
- [ ] G.1X workers for standard transforms (G.2X for memory-intensive joins)
- [ ] Workflow: crawler success triggers transform job
- [ ] Spark UI logs to S3 for post-job debugging
- [ ] CloudWatch metrics + continuous logging
- [ ] Data Catalog as schema registry (used by Athena, Redshift Spectrum)
- [ ] IAM: Glue role with least-privilege on source/target buckets