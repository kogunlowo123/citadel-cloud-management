# GKE Autopilot with Monitoring: Production Kubernetes on GCP

**Pillar:** GCP Infrastructure
**SEO Target:** gke autopilot terraform monitoring production
**Word Count:** ~1600

GKE Autopilot removes node management entirely — Google provisions and scales nodes automatically, charges per pod rather than per node, and enforces security policies by default. This guide deploys GKE Autopilot with Terraform and wires up full observability: Cloud Monitoring dashboards, alerting, and log-based metrics.

## Why Autopilot Over Standard GKE

| Feature | Autopilot | Standard |
|---------|-----------|---------|
| Node management | Google managed | You manage |
| Billing | Per pod CPU/memory | Per node |
| Security | Enforced pod security | You configure |
| Idle cost | Zero (no idle nodes) | Idle nodes cost money |
| Node pools | Not needed | Required |
| Surge upgrades | Automatic | Manual config |

For most production workloads, Autopilot cuts operational overhead by ~60% and reduces costs by 30–40% vs. Standard with equivalent workloads.

## Cluster

```hcl
resource "google_container_cluster" "autopilot" {
  name     = "${var.prefix}-${var.environment}"
  location = var.region
  project  = var.project_id

  enable_autopilot = true

  networking_mode = "VPC_NATIVE"
  network         = var.vpc_name
  subnetwork      = var.subnet_name

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  addons_config {
    horizontal_pod_autoscaling { disabled = false }
    http_load_balancing { disabled = false }
    gce_persistent_disk_csi_driver_config { enabled = true }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.gke_nodes.email
      oauth_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS"
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "POD",
      "DAEMONSET",
      "DEPLOYMENT",
      "STATEFULSET",
      "HPA",
      "STORAGE",
      "CADVISOR",
      "KUBELET"
    ]

    managed_prometheus { enabled = true }
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  labels = var.labels
}
```

## Workload Identity for Applications

```hcl
resource "google_service_account" "app" {
  account_id   = "${var.prefix}-app-sa"
  display_name = "GKE Application SA"
  project      = var.project_id
}

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.k8s_service_account_name}]"
}
```

## Cloud Monitoring Dashboard

```hcl
resource "google_monitoring_dashboard" "gke" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "${var.prefix} GKE Autopilot Dashboard"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "CPU Utilization by Pod"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"k8s_container\" resource.labels.cluster_name=\"${google_container_cluster.autopilot.name}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields      = ["resource.labels.pod_name"]
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Memory Usage by Pod"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"kubernetes.io/container/memory/used_bytes\" resource.labels.cluster_name=\"${google_container_cluster.autopilot.name}\""
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })
}
```

## Alerting Policies

```hcl
resource "google_monitoring_alert_policy" "pod_restarts" {
  project      = var.project_id
  display_name = "${var.prefix} Pod Restart Rate High"

  conditions {
    display_name = "Pod restart count > 5 in 5 minutes"
    condition_threshold {
      filter          = "resource.type=\"k8s_pod\" resource.labels.cluster_name=\"${google_container_cluster.autopilot.name}\" metric.type=\"kubernetes.io/pod/restart_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "oom_killed" {
  project      = var.project_id
  display_name = "${var.prefix} OOMKilled Containers"

  conditions {
    display_name = "OOMKilled containers detected"
    condition_threshold {
      filter          = "resource.type=\"k8s_container\" resource.labels.cluster_name=\"${google_container_cluster.autopilot.name}\" metric.type=\"kubernetes.io/container/memory/limit_utilization\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.95
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}

resource "google_monitoring_alert_policy" "node_not_ready" {
  project      = var.project_id
  display_name = "${var.prefix} Node NotReady"

  conditions {
    display_name = "Node condition NotReady"
    condition_threshold {
      filter     = "resource.type=\"k8s_node\" resource.labels.cluster_name=\"${google_container_cluster.autopilot.name}\" metric.type=\"kubernetes.io/node/condition/ready\""
      duration   = "120s"
      comparison = "COMPARISON_LT"
      threshold_value = 1
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}
```

## Notification Channel

```hcl
resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "${var.prefix} Alerts Email"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}
```

## Log-Based Metrics

```hcl
resource "google_logging_metric" "security_events" {
  project = var.project_id
  name    = "${var.prefix}_k8s_security_events"
  filter  = "resource.type=\"k8s_cluster\" AND logName:\"cloudaudit.googleapis.com\" AND severity>=\"WARNING\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "severity"
      value_type  = "STRING"
      description = "Log severity"
    }
  }

  label_extractors = {
    severity = "EXTRACT(severity)"
  }
}
```

## Outputs

```hcl
output "cluster_name" {
  value = google_container_cluster.autopilot.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.autopilot.endpoint
  sensitive = true
}

output "workload_pool" {
  value = google_container_cluster.autopilot.workload_identity_config[0].workload_pool
}
```

## Production Checklist

- [ ] Private nodes with no public IPs
- [ ] Master authorized networks restricts API server access
- [ ] Workload Identity enabled (no node service account keys)
- [ ] Binary Authorization in enforcement mode
- [ ] Managed Prometheus for metrics
- [ ] All monitoring components enabled
- [ ] Log-based metrics for security events
- [ ] Alerting on pod restarts, OOM kills, and node NotReady
- [ ] REGULAR release channel for stable, tested updates
- [ ] VPC-native networking (alias IPs, no node routes)

GKE Autopilot with Managed Prometheus and Cloud Monitoring gives you a fully observable, fully managed Kubernetes platform where you focus on workloads, not cluster operations.
