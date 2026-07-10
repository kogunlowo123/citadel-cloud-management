# AWS CloudWatch Observability: Metrics, Logs, and Alarms with Terraform

**Pillar:** AWS Infrastructure
**SEO Target:** aws cloudwatch terraform observability metrics logs alarms dashboards
**Word Count:** ~1600

CloudWatch is AWS's native observability platform. Used correctly, it surfaces application health issues before users notice. This guide implements production-grade CloudWatch observability with Terraform: structured logging, composite alarms, anomaly detection, and dashboards.

## Log Groups with Retention

```hcl
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.prefix}/app"
  retention_in_days = var.environment == "prod" ? 90 : 14
  kms_key_id        = aws_kms_key.cloudwatch.arn
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/vpc/${var.vpc_id}/flow-logs"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.cloudwatch.arn
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "rds" {
  name              = "/aws/rds/cluster/${var.db_cluster_id}/postgresql"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.cloudwatch.arn
  tags              = var.tags
}
```

## Metric Filters for Structured Logs

```hcl
resource "aws_cloudwatch_log_metric_filter" "error_rate" {
  name           = "${var.prefix}-error-rate"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "[timestamp, requestId, level=\"ERROR\", ...]"

  metric_transformation {
    name          = "ErrorCount"
    namespace     = "CitadelApp/${var.environment}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "latency" {
  name           = "${var.prefix}-latency"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "[timestamp, requestId, level, message, duration]"

  metric_transformation {
    name          = "RequestLatency"
    namespace     = "CitadelApp/${var.environment}"
    value         = "$duration"
    default_value = "0"
    unit          = "Milliseconds"
  }
}

resource "aws_cloudwatch_log_metric_filter" "http_5xx" {
  name           = "${var.prefix}-5xx-errors"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "[timestamp, requestId, status_code=5*, method, path, duration]"

  metric_transformation {
    name      = "HTTP5xxCount"
    namespace = "CitadelApp/${var.environment}"
    value     = "1"
  }
}
```

## Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "error_rate_high" {
  alarm_name          = "${var.prefix}-error-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorCount"
  namespace           = "CitadelApp/${var.environment}"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Error count exceeds 10/minute for 2 consecutive periods"

  alarm_actions             = [aws_sns_topic.alerts.arn]
  ok_actions                = [aws_sns_topic.alerts.arn]
  insufficient_data_actions = []

  treat_missing_data = "notBreaching"
  tags               = var.tags
}

resource "aws_cloudwatch_metric_alarm" "latency_p99_high" {
  alarm_name          = "${var.prefix}-latency-p99-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "RequestLatency"
  namespace           = "CitadelApp/${var.environment}"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 2000
  alarm_description   = "P99 latency > 2s for 15 minutes"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.prefix}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "ECS CPU > 85% for 3 consecutive minutes"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}
```

## Anomaly Detection Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "request_count_anomaly" {
  alarm_name          = "${var.prefix}-request-count-anomaly"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "e1"
  alarm_description   = "Request count anomaly — possible traffic spike or DDoS"

  metric_query {
    id          = "m1"
    return_data = false
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  metric_query {
    id          = "e1"
    return_data = true
    expression  = "ANOMALY_DETECTION_BAND(m1, 3)"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

## Composite Alarm

```hcl
resource "aws_cloudwatch_composite_alarm" "service_health" {
  alarm_name = "${var.prefix}-service-health"
  alarm_description = "Overall service health — triggers when multiple signals indicate issues"

  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.error_rate_high.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.latency_p99_high.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.ecs_cpu_high.alarm_name})"
  ])

  alarm_actions             = [aws_sns_topic.pagerduty.arn]
  ok_actions                = [aws_sns_topic.pagerduty.arn]
  insufficient_data_actions = []
  tags                      = var.tags
}
```

## CloudWatch Dashboard

```hcl
resource "aws_cloudwatch_dashboard" "app" {
  dashboard_name = "${var.prefix}-app-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "Request Volume & Error Rate"
          period = 60
          metrics = [
            ["CitadelApp/${var.environment}", "ErrorCount", { stat = "Sum", color = "#d62728" }],
            ["CitadelApp/${var.environment}", "HTTP5xxCount", { stat = "Sum", color = "#ff7f0e" }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "Latency Percentiles"
          period = 60
          metrics = [
            ["CitadelApp/${var.environment}", "RequestLatency", { stat = "p50", label = "p50" }],
            ["CitadelApp/${var.environment}", "RequestLatency", { stat = "p95", label = "p95" }],
            ["CitadelApp/${var.environment}", "RequestLatency", { stat = "p99", label = "p99", color = "#d62728" }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "alarm"
        width  = 24
        height = 4
        properties = {
          title = "Service Alarms"
          alarms = [
            aws_cloudwatch_composite_alarm.service_health.arn,
            aws_cloudwatch_metric_alarm.error_rate_high.arn,
            aws_cloudwatch_metric_alarm.latency_p99_high.arn
          ]
        }
      }
    ]
  })
}
```

## SNS Topic + Slack Integration

```hcl
resource "aws_sns_topic" "alerts" {
  name              = "${var.prefix}-alerts"
  kms_master_key_id = "alias/aws/sns"
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "lambda_slack" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}
```

## Production Checklist

- [ ] Log groups with KMS encryption and appropriate retention (90d prod, 14d staging)
- [ ] Metric filters on structured logs (error count, latency, HTTP 5xx)
- [ ] Individual alarms: error rate, P99 latency, CPU, memory
- [ ] Anomaly detection on request volume (catches DDoS and traffic spikes)
- [ ] Composite alarm for overall service health (single PagerDuty trigger)
- [ ] CloudWatch Dashboard covering request volume, latency, and alarm status
- [ ] SNS with email + Slack/PagerDuty subscriptions
- [ ] Container Insights on ECS cluster
- [ ] VPC Flow Logs captured to CloudWatch

CloudWatch observability done right gives you signal on application health before it becomes an incident. The composite alarm pattern is key — route composite alarms to PagerDuty and individual alarms to Slack to avoid alert fatigue.
