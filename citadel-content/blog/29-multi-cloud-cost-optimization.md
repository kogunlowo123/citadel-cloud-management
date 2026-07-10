# Multi-Cloud Cost Optimization: AWS, Azure, and GCP in 2026

**Pillar:** Multi-Cloud Architecture
**SEO Target:** multi-cloud cost optimization aws azure gcp terraform
**Word Count:** ~1700

Cloud costs spiral without active management. A multi-cloud architecture amplifies this risk — waste on three platforms compounds. This guide covers Terraform-driven cost optimization strategies across AWS, Azure, and GCP, with real patterns that reduce bills by 30–60%.

## The Multi-Cloud Cost Problem

Running workloads on multiple clouds multiplies your cost surface:
- Data transfer charges between clouds
- Duplicate licensing for monitoring/security tools
- Unused reserved capacity on each platform
- Inconsistent tagging makes attribution impossible

Structured cost optimization turns this liability into an advantage — using each cloud for what it does cheapest.

## Layer 1: Tagging Strategy (Non-Negotiable First Step)

Without consistent tags, you can't attribute cost, can't build chargebacks, and can't identify waste.

```hcl
# Shared tagging module
locals {
  mandatory_tags = {
    environment  = var.environment
    team         = var.team
    project      = var.project
    cost_center  = var.cost_center
    managed_by   = "terraform"
    created_date = formatdate("YYYY-MM-DD", timestamp())
  }
}

# AWS
resource "aws_resourcegroups_group" "cost_tracking" {
  name = "${var.project}-${var.environment}"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        { Key = "project"; Values = [var.project] },
        { Key = "environment"; Values = [var.environment] }
      ]
    })
  }
}

# Azure
resource "azurerm_resource_group" "main" {
  name     = "${var.project}-${var.environment}-rg"
  location = var.location
  tags     = local.mandatory_tags
}

# GCP
resource "google_project_label" "cost_labels" {
  project = var.project_id
  labels  = {
    environment = var.environment
    team        = var.team
    project     = replace(var.project, "-", "_")
  }
}
```

## Layer 2: Right-Sizing with Terraform

### AWS — Auto Scaling with Predictive Scaling

```hcl
resource "aws_autoscaling_policy" "predictive" {
  name                   = "${var.name}-predictive"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "PredictiveScaling"

  predictive_scaling_configuration {
    mode                         = "ForecastAndScale"
    scheduling_buffer_time       = 300

    metric_specification {
      target_utilization = 70

      predefined_scaling_metric_specification {
        predefined_metric_type = "ASGAverageCPUUtilization"
      }
    }
  }
}
```

### Azure — Auto-scale on VMSS

```hcl
resource "azurerm_monitor_autoscale_setting" "main" {
  name                = "${var.prefix}-autoscale"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.main.id

  profile {
    name = "default"
    capacity {
      default = 2
      minimum = 1
      maximum = 10
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}
```

## Layer 3: Spot/Preemptible for Batch Workloads

### AWS Spot Instances (up to 90% savings)

```hcl
resource "aws_spot_fleet_request" "batch" {
  iam_fleet_role  = aws_iam_role.spot_fleet.arn
  target_capacity = var.batch_capacity
  spot_price      = "0.05"

  launch_specification {
    instance_type     = "m5.xlarge"
    ami               = data.aws_ami.amazon_linux.id
    subnet_id         = var.private_subnet_id
    iam_instance_profile = aws_iam_instance_profile.batch.name
  }

  launch_specification {
    instance_type     = "m5a.xlarge"
    ami               = data.aws_ami.amazon_linux.id
    subnet_id         = var.private_subnet_id
    iam_instance_profile = aws_iam_instance_profile.batch.name
  }

  allocation_strategy                 = "lowestPrice"
  instance_interruption_behaviour     = "terminate"
  wait_for_fulfillment                = true
}
```

### GCP Preemptible VMs

```hcl
resource "google_compute_instance" "batch" {
  name         = "${var.prefix}-batch"
  machine_type = "n2-standard-4"
  zone         = var.zone
  project      = var.project_id

  scheduling {
    preemptible        = true
    automatic_restart  = false
    on_host_maintenance = "TERMINATE"
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = var.vpc_name
    subnetwork = var.subnet_name
  }
}
```

## Layer 4: Reserved/Committed Use Discounts

### AWS Compute Savings Plans (Terraform)

```hcl
resource "aws_savingsplans_plan" "compute" {
  count = var.enable_savings_plan ? 1 : 0

  # Note: Savings Plans purchases are managed in AWS console
  # Use the cost-and-usage-report for tracking:
  resource "aws_cur_report_definition" "main" {
    report_name                = "${var.prefix}-cost-usage-report"
    time_unit                  = "HOURLY"
    format                     = "Parquet"
    compression                = "Parquet"
    s3_bucket                  = aws_s3_bucket.cost_reports.bucket
    s3_region                  = var.region
    s3_prefix                  = "cost-usage-reports"
    additional_schema_elements = ["RESOURCES", "SPLIT_COST_ALLOCATION_DATA"]
    report_versioning          = "OVERWRITE_REPORT"
    refresh_closed_reports     = true
  }
}
```

### GCP Committed Use Discounts

```hcl
resource "google_compute_resource_policy" "cud" {
  name    = "${var.prefix}-cud-policy"
  region  = var.region
  project = var.project_id

  # GCP CUDs are purchased in console, but you can tag for tracking:
  # Use labels on instances to associate with CUD commitments
}
```

## Layer 5: Storage Lifecycle Policies

### AWS S3 Intelligent Tiering

```hcl
resource "aws_s3_bucket_intelligent_tiering_configuration" "main" {
  bucket = var.bucket_name
  name   = "EntireBucket"

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }
}
```

### Azure Blob Lifecycle

```hcl
resource "azurerm_storage_management_policy" "lifecycle" {
  storage_account_id = var.storage_account_id

  rule {
    name    = "tiering-rule"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = 365
      }
      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
    }
  }
}
```

## Layer 6: Budget Alerts

```hcl
# AWS Budget
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_alert_emails
  }
}

# GCP Budget
resource "google_billing_budget" "main" {
  billing_account = var.billing_account_id
  display_name    = "${var.project}-monthly-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }
}
```

## Expected Savings

| Optimization | AWS Savings | Azure Savings | GCP Savings |
|-------------|-------------|---------------|-------------|
| Right-sizing (80% target) | 20–30% | 15–25% | 20–30% |
| Spot/Preemptible for batch | 70–90% | 60–80% | 70–80% |
| Reserved/CUDs (1yr) | 30–40% | 35–45% | 25–35% |
| Storage lifecycle | 40–60% | 30–50% | 40–60% |
| Predictive auto-scaling | 15–25% | 10–20% | 15–20% |

Combined, a well-optimized multi-cloud workload typically runs 40–60% cheaper than an unmanaged equivalent with the same performance profile.

## Production Checklist

- [ ] Mandatory tags enforced via Terraform (no resource without tags)
- [ ] Cost and Usage Reports (AWS) + Billing Export (GCP) → data warehouse
- [ ] Monthly budget alerts at 80% and 100% forecast
- [ ] Spot/Preemptible for all non-critical batch workloads
- [ ] S3/Blob/GCS intelligent tiering on all object storage
- [ ] Reserved instances for production steady-state compute
- [ ] Predictive scaling for web tier (eliminates over-provisioning)
- [ ] Weekly FinOps review meeting with platform and engineering teams

Cost optimization isn't a one-time project — it's a continuous practice embedded in your Terraform modules and reviewed weekly.
