# KEDA: Event-Driven Autoscaling for Kubernetes with Terraform

**Pillar:** AWS Infrastructure
**SEO Target:** keda kubernetes autoscaling terraform, keda eks terraform, kubernetes event driven autoscaling
**Word Count:** ~1,800

KEDA (Kubernetes Event-Driven Autoscaling) extends Kubernetes HPA to scale deployments based on external event sources — SQS queue depth, Kafka lag, Redis list length, Prometheus metrics, scheduled cron, and 60+ other scalers. Unlike vanilla HPA which only scales on CPU/memory, KEDA can scale your deployment to zero when idle and back to N replicas in seconds when events arrive. This guide deploys KEDA on EKS with Terraform and configures SQS, Prometheus, and cron-based scaling.

## KEDA Architecture

```
External Event Source (SQS, Kafka, Redis, Prometheus)
        ↓
KEDA ScaledObject watches queue depth / metric
        ↓
KEDA Operator → adjusts HPA target replicas
        ↓
HPA scales Deployment (0 → N replicas)
```

Key concepts:
- **ScaledObject** — links a Deployment to a scaler and defines min/max replicas
- **TriggerAuthentication** — stores credentials for external event sources (SQS, Redis, etc.)
- **ScaledJob** — for batch workloads (scale to zero between jobs)

## Install KEDA with Helm

```hcl
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.15.0"
  namespace        = "keda"
  create_namespace = true

  set {
    name  = "podIdentity.aws.irsa.enabled"
    value = "true"
  }

  set {
    name  = "podIdentity.aws.irsa.roleArn"
    value = aws_iam_role.keda.arn
  }

  set {
    name  = "resources.operator.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.operator.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "resources.operator.limits.cpu"
    value = "500m"
  }

  set {
    name  = "resources.operator.limits.memory"
    value = "512Mi"
  }

  depends_on = [aws_eks_cluster.main]
}
```

## IAM Role for KEDA (IRSA)

```hcl
resource "aws_iam_role" "keda" {
  name = "${var.prefix}-keda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider}:sub" = "system:serviceaccount:keda:keda-operator"
          "${local.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "keda_sqs" {
  name = "keda-sqs-policy"
  role = aws_iam_role.keda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ListQueues"
        ]
        Resource = [
          aws_sqs_queue.work_queue.arn,
          "${aws_sqs_queue.work_queue.arn}/*"
        ]
      }
    ]
  })
}
```

## SQS-Based Scaling

```hcl
# The SQS queue
resource "aws_sqs_queue" "work_queue" {
  name                       = "${var.prefix}-work-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
  kms_master_key_id          = aws_kms_key.sqs.arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.work_dlq.arn
    maxReceiveCount     = 3
  })

  tags = var.tags
}

# ScaledObject: scale workers based on SQS queue depth
resource "kubernetes_manifest" "sqs_scaler" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "sqs-worker-scaler"
      namespace = "workers"
    }
    spec = {
      scaleTargetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = "sqs-worker"
      }
      minReplicaCount = 0  # Scale to zero when queue is empty
      maxReplicaCount = 50
      pollingInterval = 15  # Check queue every 15s
      cooldownPeriod  = 300  # Wait 5m before scaling down

      triggers = [{
        type = "aws-sqs-queue"
        authenticationRef = {
          name = "keda-aws-credentials"
        }
        metadata = {
          queueURL                = aws_sqs_queue.work_queue.url
          queueLength             = "5"   # 1 worker per 5 messages
          awsRegion               = var.region
          scaleOnInFlight         = "true"
          activationQueueLength   = "1"   # Wake from 0 when first message arrives
        }
      }]

      advanced = {
        restoreToOriginalReplicaCount = false
        horizontalPodAutoscalerConfig = {
          behavior = {
            scaleDown = {
              stabilizationWindowSeconds = 300
              policies = [{
                type          = "Percent"
                value         = 50
                periodSeconds = 60
              }]
            }
            scaleUp = {
              stabilizationWindowSeconds = 0  # Scale up immediately
              policies = [{
                type          = "Percent"
                value         = 100
                periodSeconds = 30
              }]
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.keda]
}
```

## Prometheus-Based Scaling

```hcl
# Scale API pods based on request rate from Prometheus
resource "kubernetes_manifest" "prometheus_scaler" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "api-prometheus-scaler"
      namespace = "api"
    }
    spec = {
      scaleTargetRef = {
        name = "api-deployment"
      }
      minReplicaCount = 2
      maxReplicaCount = 20

      triggers = [{
        type = "prometheus"
        metadata = {
          serverAddress = "http://prometheus-server.monitoring.svc.cluster.local"
          metricName    = "http_requests_per_second"
          query         = "sum(rate(http_requests_total{service='api-service'}[2m]))"
          threshold     = "50"  # 1 pod per 50 req/s
          activationThreshold = "5"
        }
      }]
    }
  }
}
```

## Cron-Based Scaling (Business Hours)

```hcl
# Scale up before business hours, scale down at night
resource "kubernetes_manifest" "cron_scaler" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "api-cron-scaler"
      namespace = "api"
    }
    spec = {
      scaleTargetRef = {
        name = "api-deployment"
      }
      minReplicaCount = 1
      maxReplicaCount = 20

      triggers = [
        {
          type = "cron"
          metadata = {
            timezone        = "America/Chicago"
            start           = "0 7 * * 1-5"   # Monday–Friday 7 AM
            end             = "0 19 * * 1-5"   # Monday–Friday 7 PM
            desiredReplicas = "5"
          }
        },
        # Combine with SQS for event-driven scaling during business hours
        {
          type = "aws-sqs-queue"
          authenticationRef = { name = "keda-aws-credentials" }
          metadata = {
            queueURL      = aws_sqs_queue.work_queue.url
            queueLength   = "10"
            awsRegion     = var.region
          }
        }
      ]
    }
  }
}
```

## ScaledJob for Batch Processing

```hcl
# For batch jobs: create a Job per message, not a long-running Deployment
resource "kubernetes_manifest" "batch_scaler" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledJob"
    metadata = {
      name      = "batch-processor"
      namespace = "batch"
    }
    spec = {
      jobTargetRef = {
        template = {
          spec = {
            containers = [{
              name    = "batch-worker"
              image   = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/batch-worker:latest"
              command = ["python", "process.py"]
            }]
            restartPolicy = "Never"
          }
        }
        backoffLimit = 2
      }
      minReplicaCount = 0
      maxReplicaCount = 100
      rollout = {
        strategy             = "gradual"
        propagationPolicy    = "foreground"
      }
      scalingStrategy = {
        strategy          = "accurate"  # One job per message
        pendingJobsCount  = 2           # Keep 2 ahead for warm processing
      }
      triggers = [{
        type = "aws-sqs-queue"
        authenticationRef = { name = "keda-aws-credentials" }
        metadata = {
          queueURL     = aws_sqs_queue.batch_queue.url
          queueLength  = "1"  # Exactly 1 job per SQS message
          awsRegion    = var.region
        }
      }]
    }
  }
}
```

## TriggerAuthentication (IRSA)

```hcl
# Use IRSA instead of static credentials
resource "kubernetes_manifest" "keda_auth" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "TriggerAuthentication"
    metadata = {
      name      = "keda-aws-credentials"
      namespace = "workers"
    }
    spec = {
      podIdentity = {
        provider = "aws"  # Use IRSA, no static keys
      }
    }
  }
}
```

## CloudWatch Monitoring

```hcl
resource "aws_cloudwatch_metric_alarm" "keda_max_replicas" {
  alarm_name          = "${var.prefix}-keda-at-max-replicas"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  namespace           = "keda"
  metric_name         = "keda_scaler_active"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1

  dimensions = {
    namespace   = "workers"
    scaledObject = "sqs-worker-scaler"
  }

  alarm_description = "KEDA workers at max replicas — may need queue capacity review"
  alarm_actions     = [aws_sns_topic.alerts.arn]
}
```

## Production Checklist

- [ ] KEDA installed with IRSA (not static credentials)
- [ ] `minReplicaCount = 0` only for stateless workers, not stateful services
- [ ] `activationQueueLength` set to wake from zero on first message
- [ ] `cooldownPeriod` >= 300s to avoid flapping
- [ ] Scale-up policy: 100%/30s for fast burst; scale-down: 50%/60s with 300s stabilization
- [ ] SQS `visibility_timeout_seconds` > job processing time
- [ ] Dead-letter queue configured (prevent infinite reprocessing on failures)
- [ ] Prometheus scaler tested with `kubectl get hpa` to verify KEDA sets correct targets
- [ ] ScaledJob used for batch (not Deployment) when each message = one job
- [ ] CloudWatch alarm when workers hit max replicas
- [ ] KEDA metrics port exposed for Prometheus scraping (port 9090)

KEDA's 60+ scalers cover virtually every event source — SQS, Kafka, Redis, Prometheus, Datadog, MySQL, Azure Service Bus, Pub/Sub, and more — making it the standard for event-driven scaling on Kubernetes.
