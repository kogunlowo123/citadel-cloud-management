---
title: "GKE Autopilot with Terraform: Production Kubernetes Without Node Management"
published: true
description: "Deploy GKE Autopilot with Terraform: VPC-native clusters, Workload Identity, Binary Authorization, and cost-optimized auto-provisioning — no node pools to manage."
tags: gcp, terraform, kubernetes, devops
series: "Citadel Cloud Management: 100 Free Terraform Guides"
canonical_url: https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/11-gke-autopilot-terraform-guide.md
cover_image: ""
---

GKE Autopilot removes node management from Kubernetes operations. No node sizing, no node pool scaling, no OS patching. You define Pods and GKE provisions exactly the compute they need — and you only pay for what those Pods consume.

For most production web services, APIs, and data pipelines, Autopilot is the right default. Here is how to deploy a production-ready GKE Autopilot cluster with Terraform.

## Autopilot vs Standard Mode

Before writing any Terraform, choose the right mode for your workload.

| Factor | Autopilot | Standard |
|--------|-----------|----------|
| Node management | GKE managed | You manage |
| Pricing model | Per Pod (CPU/memory/storage) | Per node |
| GPU workloads | Limited support | Full support |
| DaemonSets | Not supported | Supported |
| Node customization | Not available | Full control |
| Scaling speed | Fast (no node bootstrap wait) | Depends on node pool config |
| OS patching | Automatic | Manual or node auto-upgrade |
| Bin packing control | None | Full |
| Best for | Web/API/pipeline workloads | ML training, custom hardware |
| Idle cost | Near zero | Node costs continue |

Choose Autopilot unless you need GPUs at scale, custom kernel modules, or DaemonSets. If you are unsure, start with Autopilot — you can migrate workloads to a Standard cluster later.

## Core Cluster Resource

```hcl
resource "google_container_cluster" "main" {
  name     = "production-gke"
  location = var.region
  project  = var.project_id

  # Enable Autopilot mode — this is the key setting
  enable_autopilot = true

  # VPC-native networking (alias IP ranges)
  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.main.name
  subnetwork      = google_compute_subnetwork.gke.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster — nodes have no public IPs
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false  # Set true only with VPN or Interconnect
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Restrict API server access
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.corporate_cidr
      display_name = "Corporate Network"
    }
    cidr_blocks {
      cidr_block   = var.vpn_cidr
      display_name = "Corporate VPN"
    }
  }

  # Workload Identity — no service account keys in Pods
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Binary Authorization — only allow verified images
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Protect against accidental deletion
  deletion_protection = true

  release_channel {
    channel = "REGULAR"
  }
}
```

## VPC-Native Networking

Autopilot clusters require VPC-native networking with alias IP ranges. Create a subnet with secondary ranges for Pods and Services before provisioning the cluster.

```hcl
resource "google_compute_subnetwork" "gke" {
  name          = "gke-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.main.id
  project       = var.project_id

  # Secondary range for Pod IPs
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  # Secondary range for Service ClusterIPs
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.0.16.0/20"
  }

  private_ip_google_access = true
}
```

## Workload Identity Setup

Workload Identity lets Pods authenticate to GCP APIs without service account keys. This is the required approach for Autopilot — avoid mounting key files entirely.

```hcl
# GCP service account for the application
resource "google_service_account" "app" {
  account_id   = "app-workload-sa"
  display_name = "Application Workload Service Account"
  project      = var.project_id
}

# Grant the GCP SA the permissions it needs
resource "google_project_iam_member" "app_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Allow the Kubernetes SA to impersonate the GCP SA
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[production/app-ksa]"
}

# Kubernetes service account with the annotation
resource "kubernetes_service_account" "app" {
  metadata {
    name      = "app-ksa"
    namespace = "production"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.app.email
    }
  }

  depends_on = [google_container_cluster.main]
}
```

## Node Auto-Provisioning and Resource Requests

In Autopilot, every Pod must declare resource requests. GKE uses these to provision exactly the right compute. Under-specified Pods will be mutated or rejected.

```hcl
# Example: Kubernetes Deployment with proper resource requests
resource "kubernetes_deployment" "api" {
  metadata {
    name      = "api-server"
    namespace = "production"
  }

  spec {
    replicas = 3

    selector {
      match_labels = { app = "api-server" }
    }

    template {
      metadata {
        labels = { app = "api-server" }
      }

      spec {
        service_account_name = kubernetes_service_account.app.metadata[0].name

        container {
          name  = "api"
          image = "gcr.io/${var.project_id}/api:latest"

          # Resource requests are REQUIRED in Autopilot
          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          port {
            container_port = 8080
          }
        }
      }
    }
  }
}
```

## Binary Authorization Policy

Binary Authorization enforces that only images from trusted registries and signing authorities can run in your cluster.

```hcl
resource "google_binary_authorization_policy" "default" {
  project = var.project_id

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"

    require_attestations_by = [
      google_binary_authorization_attestor.build_pipeline.name
    ]
  }

  # Allow GKE system images without attestation
  global_policy_evaluation_mode = "ENABLE"
}

resource "google_binary_authorization_attestor" "build_pipeline" {
  name    = "build-pipeline-attestor"
  project = var.project_id

  attestation_authority_note {
    note_reference = google_container_note.build_note.name

    public_keys {
      id = data.google_kms_crypto_key_version.attestor_key.id
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.attestor_key.public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.attestor_key.public_key[0].algorithm
      }
    }
  }
}
```

## Production Checklist

Before this cluster handles production traffic, verify every item:

- [ ] `enable_autopilot = true` is set (cannot change post-creation)
- [ ] `networking_mode = "VPC_NATIVE"` with secondary IP ranges defined
- [ ] `enable_private_nodes = true` — no public IPs on nodes
- [ ] `master_authorized_networks_config` restricts API server access to known CIDRs
- [ ] `workload_identity_config` enabled — no service account key files in Pods
- [ ] All Pods declare explicit CPU and memory `requests`
- [ ] `binary_authorization` set to `PROJECT_SINGLETON_POLICY_ENFORCE`
- [ ] `release_channel` set to `REGULAR` or `STABLE` — never `RAPID` in production
- [ ] `deletion_protection = true` — prevents accidental `terraform destroy`
- [ ] `managed_prometheus.enabled = true` for GKE-native metrics collection
- [ ] Namespaces and RBAC configured before deploying workloads
- [ ] Pod Disruption Budgets defined for all stateful or critical workloads

## Key Outputs

```hcl
output "cluster_endpoint" {
  value     = google_container_cluster.main.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "workload_identity_pool" {
  value = "${var.project_id}.svc.id.goog"
}
```

## What You Get

A production GKE Autopilot cluster built with Terraform gives you:

- **Zero node management** — GKE provisions and patches all compute automatically
- **Pay-per-Pod billing** — no charges for idle node capacity
- **Workload Identity** — GCP API authentication without credentials in containers
- **Binary Authorization** — cryptographic enforcement of your image supply chain
- **VPC-native networking** — Pods are first-class VPC citizens, accessible directly from other GCP services
- **Managed Prometheus** — metrics collection without running your own Prometheus stack

The full module with variables, outputs, and examples is available at [Citadel Cloud Management](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/11-gke-autopilot-terraform-guide.md).
