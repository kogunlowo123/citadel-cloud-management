# Google Vertex AI with Terraform: ML Platform Infrastructure

**Pillar:** AI/ML Engineering
**SEO Target:** vertex ai terraform machine learning infrastructure
**Word Count:** ~1700

Google Vertex AI is the unified ML platform on GCP — it covers dataset management, model training, model registry, online/batch prediction, and the Generative AI API (Gemini). This guide deploys Vertex AI infrastructure with Terraform: Workbench notebooks, Training pipelines, Endpoints, and Feature Store.

## Architecture

A production Vertex AI setup includes:
- Managed notebooks (Vertex AI Workbench) for development
- Training pipelines with custom containers
- Model Registry for versioning
- Online Endpoints for low-latency inference
- Feature Store for serving ML features
- Artifact Registry for training images

## Project APIs

```hcl
resource "google_project_service" "vertex_ai" {
  project = var.project_id
  service = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "notebooks" {
  project = var.project_id
  service = "notebooks.googleapis.com"
  disable_on_destroy = false
}
```

## Artifact Registry for Training Images

```hcl
resource "google_artifact_registry_repository" "ml_images" {
  project       = var.project_id
  location      = var.region
  repository_id = "${var.prefix}-ml-images"
  format        = "DOCKER"
  description   = "ML training container images"

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  labels = var.labels
}
```

## Workbench Instance (Managed Notebook)

```hcl
resource "google_workbench_instance" "notebook" {
  name     = "${var.prefix}-notebook-${var.environment}"
  location = "${var.region}-a"
  project  = var.project_id

  gce_setup {
    machine_type = var.notebook_machine_type

    accelerator_configs {
      type       = "NVIDIA_TESLA_T4"
      core_count = 1
    }

    boot_disk {
      disk_size_gb = 100
      disk_type    = "PD_SSD"
    }

    data_disks {
      disk_size_gb = 500
      disk_type    = "PD_SSD"
    }

    service_accounts {
      email = google_service_account.notebook.email
    }

    network_interfaces {
      network    = var.vpc_id
      subnet     = var.subnet_id
      nic_type   = "GVNIC"
    }

    disable_public_ip = true

    metadata = {
      notebook-disable-root = "true"
      serial-port-enable    = "false"
    }

    enable_ip_forwarding = false
  }

  labels = var.labels
}

resource "google_service_account" "notebook" {
  account_id   = "${var.prefix}-notebook-sa"
  display_name = "Vertex AI Notebook SA"
  project      = var.project_id
}

resource "google_project_iam_member" "notebook_vertex" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.notebook.email}"
}
```

## Training Pipeline

```hcl
# Training service account
resource "google_service_account" "training" {
  account_id   = "${var.prefix}-training-sa"
  display_name = "Vertex AI Training SA"
  project      = var.project_id
}

resource "google_project_iam_member" "training_vertex" {
  project = var.project_id
  role    = "roles/aiplatform.serviceAgent"
  member  = "serviceAccount:${google_service_account.training.email}"
}

resource "google_project_iam_member" "training_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.training.email}"
}

# GCS bucket for training data and artifacts
resource "google_storage_bucket" "ml_artifacts" {
  name                        = "${var.project_id}-ml-artifacts-${var.environment}"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning { enabled = true }

  lifecycle_rule {
    action { type = "Delete" }
    condition {
      age                   = 365
      matches_storage_class = ["NEARLINE", "COLDLINE"]
    }
  }

  labels = var.labels
}
```

## Feature Store

```hcl
resource "google_vertex_ai_feature_store" "main" {
  name    = "${var.prefix}_feature_store"
  project = var.project_id
  region  = var.region

  online_serving_config {
    fixed_node_count = var.feature_store_nodes
  }

  encryption_spec {
    kms_key_name = var.kms_key_name
  }

  labels = var.labels

  depends_on = [google_project_service.vertex_ai]
}

resource "google_vertex_ai_feature_store_entity_type" "user_features" {
  name         = "user_features"
  featurestore = google_vertex_ai_feature_store.main.id

  monitoring_config {
    snapshot_analysis {
      disabled = false
      monitoring_interval_days = 1
    }
  }
}
```

## Online Prediction Endpoint

```hcl
resource "google_vertex_ai_endpoint" "main" {
  name         = "${var.prefix}-endpoint-${var.environment}"
  display_name = "${var.prefix} ${var.environment} endpoint"
  project      = var.project_id
  location     = var.region

  encryption_spec {
    kms_key_name = var.kms_key_name
  }

  network = "projects/${data.google_project.main.number}/global/networks/${var.vpc_name}"

  labels = var.labels

  depends_on = [google_project_service.vertex_ai]
}
```

## Index for Vector Search

```hcl
resource "google_vertex_ai_index" "embedding_index" {
  display_name = "${var.prefix}-embedding-index"
  project      = var.project_id
  region       = var.region
  description  = "Embedding index for semantic search"

  metadata {
    contents_delta_uri = "gs://${google_storage_bucket.ml_artifacts.name}/index/embeddings/"
    config {
      dimensions                  = 768
      approximate_neighbors_count = 150
      shard_size                  = "SHARD_SIZE_MEDIUM"
      distance_measure_type       = "DOT_PRODUCT_DISTANCE"
      algorithm_config {
        tree_ah_config {
          leaf_node_embedding_count    = 1000
          leaf_nodes_to_search_percent = 10
        }
      }
    }
  }

  index_update_method = "BATCH_UPDATE"
  labels              = var.labels
}

resource "google_vertex_ai_index_endpoint" "main" {
  display_name = "${var.prefix}-index-endpoint"
  project      = var.project_id
  region       = var.region
  network      = "projects/${data.google_project.main.number}/global/networks/${var.vpc_name}"

  labels = var.labels
}
```

## Private Service Connect for Vertex AI

```hcl
resource "google_compute_global_address" "vertex_psc" {
  name          = "${var.prefix}-vertex-psc"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = var.vpc_id
}

resource "google_service_networking_connection" "vertex_vpc_connection" {
  network                 = var.vpc_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.vertex_psc.name]
}
```

## Variables

```hcl
variable "prefix" { type = string }
variable "environment" { type = string }
variable "project_id" { type = string }
variable "region" { type = string; default = "us-central1" }
variable "vpc_id" { type = string }
variable "vpc_name" { type = string }
variable "subnet_id" { type = string }
variable "kms_key_name" { type = string }
variable "notebook_machine_type" { type = string; default = "n1-standard-4" }
variable "feature_store_nodes" { type = number; default = 1 }
variable "labels" { type = map(string); default = {} }
```

## Outputs

```hcl
output "feature_store_id" {
  value = google_vertex_ai_feature_store.main.id
}

output "endpoint_id" {
  value = google_vertex_ai_endpoint.main.id
}

output "index_endpoint_id" {
  value = google_vertex_ai_index_endpoint.main.id
}

output "ml_artifacts_bucket" {
  value = google_storage_bucket.ml_artifacts.name
}

output "artifact_registry_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ml_images.repository_id}"
}
```

## Production Checklist

- [ ] All APIs enabled before resource creation
- [ ] KMS encryption on Feature Store and Endpoints
- [ ] Private networking (no public endpoints)
- [ ] Service accounts with minimum IAM permissions
- [ ] Artifact Registry cleanup policies
- [ ] GCS versioning for training artifacts
- [ ] VPC peering for Vertex AI private endpoints
- [ ] Notebook with no public IP

Vertex AI with this Terraform module gives you a fully private, encrypted ML platform where notebooks, training jobs, model endpoints, and vector search all operate inside your VPC.
