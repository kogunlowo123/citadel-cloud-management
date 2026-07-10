# AWS Kinesis Data Streams with Terraform: Real-Time Data Processing

**Pillar:** AWS Infrastructure
**SEO Target:** aws kinesis data streams terraform real-time processing analytics lambda consumer
**Word Count:** ~1400

Kinesis Data Streams provides real-time data streaming at scale. Sub-second latency, 7-day retention, and enhanced fan-out for parallel consumers. This guide deploys production Kinesis streams with Lambda consumers and CloudWatch monitoring.

## Kinesis Stream

```hcl
resource "aws_kinesis_stream" "events" {
  name             = "${var.prefix}-events"
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  retention_period          = 168
  encryption_type           = "KMS"
  kms_key_id                = aws_kms_key.kinesis.arn
  enforce_consumer_deletion = false
  tags                      = var.tags
}

resource "aws_kinesis_stream_consumer" "lambda" {
  name       = "${var.prefix}-lambda-consumer"
  stream_arn = aws_kinesis_stream.events.arn
}
```

## Lambda Consumer with Enhanced Fan-Out

```hcl
resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn                   = aws_kinesis_stream_consumer.lambda.arn
  function_name                      = aws_lambda_function.processor.arn
  starting_position                  = "LATEST"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
  parallelization_factor             = 10
  bisect_batch_on_function_error     = true
  maximum_retry_attempts             = 3

  function_response_types = ["ReportBatchItemFailures"]

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.kinesis_dlq.arn
    }
  }
}
```

## Production Checklist
- [ ] ON_DEMAND mode (auto-scales shards — no hot shard management)
- [ ] 7-day retention (168h) for replay capability
- [ ] Enhanced fan-out consumer per Lambda (2MB/s per consumer per shard)
- [ ] Parallelization factor 10 (10 Lambda invocations per shard)
- [ ] KMS encryption on stream
- [ ] DLQ on failed records
- [ ] CloudWatch alarm on GetRecords.IteratorAgeMilliseconds > 60000 (falling behind)