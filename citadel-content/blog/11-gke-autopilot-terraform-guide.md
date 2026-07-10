# GKE Autopilot with Terraform: The Production-Ready Setup

**Pillar:** GCP Infrastructure
**SEO Target:** "gke autopilot terraform", "google kubernetes engine autopilot terraform"
**Word Count:** ~1,800

---

GKE Autopilot removes node management from Kubernetes operations. No node sizing, no node pool scaling, no OS patching. You define Pods and GKE provisions the exact compute they need. For most production workloads, this is the right choice.

Here's how to deploy a production-ready GKE Autopilot cluster with Terraform.

## Autopilot vs Standard: When to Choose Each

| Factor | Autopilot | Standard |
|--------|-----------|----------|
| Node management | GKE managed | You manage |
| Pricing model | Per Pod (CPU/memory/storage) | Per node |
| GPU workloads | Limited | Full support |
| DaemonSets | Not supported | Supported |
| Node customization | Not available | Full control |
| Best for | Most web/API workloads | ML training, specialized hardware |

If you're running web services, APIs, or standard data pipelines, Autopilot wins. If you need GPU nodes, custom kernel modules, or DaemonSets, use Standard.

## The Terraform Module

```hcl
module "gke_autopilot" {
  source = "github.com/Citadel-Cloud-Management/terraform-gcp-gke"

  project_id   = var.project_id
  cluster_name = "production-gke"
  region       = "us-central1"
  cluster_mode = "AUTOPILOT"

  # Networking
  network    = google_compute_network.main.name
  subnetwork = google_compute_subnetwork.gke.name

  # Private cluster (recommended for production)
  enable_private_nodes    = true
  enable_private_endpoint = false  # True only if you have VPN/Interconnect
  master_ipv4_cidr_block  = "172.16.0.0/28"

  # Authorized networks for API access
  master_authorized_networks = [
    {
      cidr_block   = var.office_cidr
      display_name = "Corporate Office"
    },
    {
      cidr_block   = var.vpn_cidr
      display_name = "Corporate VPN"
    }
  ]

  # Workload Identity (required — don't use service account keys in Pods)
  enable_workload_identity = true

  # Logging and monitoring
  enable_cloud_logging    = true
  enable_cloud_monitoring = true

  # Binary Authorization
  enable_binary_authorization = true

  deletion_protection = true  # Prevents accidental cluster deletion
}
```

## Workload Identity: The Right Way to Authenticate

Never use service account keys in Pods. Use Workload Identity:

```hcl
# Kubernetes service account
resource "kubernetes_service_account" "app" {
  metadata {
    name      = "app-service-account"
    namespace = "production"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.app.email
    }
  }
}

# GCP service account
resource "google_service_account" "app" {
  account_id   = "app-sa"
  display_name = "Application Service Account"
  project      = var.project_id
}

# Grant the Kubernetes SA permission to impersonate the GCP SA
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[production/app-service-account]"
}
```

With this setup, Pods with the `app-service-account` Kubernetes service account automatically authenticate to GCP as `app-sa@PROJECT.iam.gserviceaccount.com`. No keys, no secrets, no rotation.

## Artifact Registry Integration

Pull container images from Artifact Registry without credentials:

```hcl
resource "google_artifact_registry_repository" "containers" {
  location      = "us-central1"
  repository_id = "production-containers"
  format        = "DOCKER"
}

# Grant GKE node SA pull access
resource "google_project_iam_member" "gke_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${module.gke_autopilot.service_account}"
}
```

## Binary Authorization

Binary Authorization ensures only signed container images run in your cluster:

```hcl
resource "google_binary_authorization_policy" "production" {
  project = var.project_id

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"

    require_attestations_by = [
      google_binary_authorization_attestor.build_system.name
    ]
  }

  # Allow GKE system images without attestation
  cluster_admission_rules {
    cluster                = "${var.region}.${module.gke_autopilot.cluster_id}"
    evaluation_mode        = "REQUIRE_ATTESTATION"
    enforcement_mode       = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  }
}
```

This prevents anyone from running arbitrary images in production — only images signed by your build system get through.

## Cost Management for Autopilot

Autopilot charges per Pod resource request. To control costs:

1. **Set appropriate resource requests** — don't over-provision CPU/memory
2. **Use Vertical Pod Autoscaler (VPA) in recommendation mode** to right-size requests
3. **Set pod disruption budgets** to allow cost-saving preemptible instance usage
4. **Use GKE cost allocation** to track spend by namespace/team

```yaml
# Right-sized resource requests
resources:
  requests:
    cpu: "100m"      # 0.1 vCPU — most API pods need this or less
    memory: "128Mi"  # Start low, VPA will recommend adjustments
  limits:
    cpu: "500m"
    memory: "512Mi"
```

## Networking: VPC-Native Mode

Autopilot clusters always use VPC-native mode (alias IPs), which gives each Pod a real VPC IP address:

```hcl
resource "google_compute_subnetwork" "gke" {
  name          = "gke-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.main.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.16.0.0/14"  # /14 = 256K Pod IPs
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.20.0.0/20"  # 4K Service IPs
  }
}
```

Size your Pod CIDR generously — you can't resize it without recreating the cluster.

## Module

[terraform-gcp-gke](https://github.com/Citadel-Cloud-Management/terraform-gcp-gke) — supports both Autopilot and Standard modes.
