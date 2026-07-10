---
title: "Deploy an Enterprise AKS Cluster with Terraform: Workload Identity, Cilium, and Microsoft Defender"
published: false
description: "Configure a production AKS cluster with Cilium networking, workload identity, node pools, and Defender using Terraform"
tags: terraform, azure, kubernetes, devops
canonical_url:
cover_image:
---

# Deploy an Enterprise AKS Cluster with Terraform: Workload Identity, Cilium, and Microsoft Defender

> **Header Image Suggestion:** An architecture diagram showing an AKS cluster with Cilium networking, multiple node pools, Azure AD workload identity flow, and Microsoft Defender integration — all within an Azure Virtual Network.

**Tags:** `#azure` `#kubernetes` `#terraform` `#devops` `#aks`

---

Azure Kubernetes Service has matured significantly over the past two years. Features that used to require third-party tools — network policies, workload identity, advanced observability — are now first-party capabilities. But configuring them correctly is where most teams struggle.

I've deployed AKS clusters across financial services, healthcare, and SaaS companies. The gap between a "hello world" AKS cluster and one that passes a security audit is enormous. This article bridges that gap using a Terraform module I maintain at [terraform-azure-aks](https://github.com/kogunlowo123/terraform-azure-aks).

## Choosing Your Network Plugin: Azure CNI Overlay vs. Kubenet

This is the first and most consequential decision you'll make. It affects pod density, network performance, IP address consumption, and which features are available to you.

### Kubenet

- Pods get IPs from a virtual network (not the VNet CIDR)
- Lower IP consumption
- Limited to 400 nodes per cluster
- No Windows node pool support
- No Azure Network Policies (only Calico)

### Azure CNI (Traditional)

- Every pod gets a VNet IP
- Consumes IP addresses rapidly — a node with 30 pods needs 31 IPs
- Better performance (no extra hop)
- Required for certain features like Virtual Nodes

### Azure CNI Overlay (Recommended)

- Pods get IPs from a private CIDR (not the VNet)
- Nodes still get VNet IPs
- Supports up to 1,000 nodes
- Best of both worlds: VNet integration without IP exhaustion

For enterprise deployments, I use Azure CNI Overlay with Cilium as the dataplane:

```hcl
module "aks" {
  source = "github.com/kogunlowo123/terraform-azure-aks"

  cluster_name        = "prod-aks-westeurope"
  resource_group_name = azurerm_resource_group.aks.name
  location            = "westeurope"
  kubernetes_version  = "1.29"

  # Network configuration
  network_plugin      = "azure"
  network_plugin_mode = "overlay"
  network_dataplane   = "cilium"
  pod_cidr            = "192.168.0.0/16"
  service_cidr        = "172.16.0.0/16"
  dns_service_ip      = "172.16.0.10"

  # VNet integration
  vnet_subnet_id = azurerm_subnet.aks_nodes.id

  network_policy = "cilium"  # Uses Cilium's policy engine

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Why Cilium as the Dataplane

Cilium replaces the default `kube-proxy` with eBPF-based networking. The practical benefits are substantial:

1. **No iptables rules.** In large clusters, iptables chains become a performance bottleneck. Cilium's eBPF programs handle packet routing at the kernel level without iptables overhead.

2. **L7 network policies.** You can write policies based on HTTP methods, paths, and headers — not just L3/L4 rules.

3. **Hubble observability.** Cilium includes Hubble, which provides real-time visibility into network flows between pods. In AKS, this integrates directly with Azure Monitor.

4. **DNS-aware policies.** Allow traffic to `*.blob.core.windows.net` without hardcoding IP ranges.

Here's a Cilium network policy that allows only GET requests to a specific API path:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-api-reads
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: backend-api
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
          rules:
            http:
              - method: GET
                path: "/api/v1/products.*"
```

This is dramatically more precise than a standard Kubernetes NetworkPolicy.

## Workload Identity: The End of Stored Credentials

Workload Identity replaces the old pod-managed identity (aad-pod-identity) approach. It uses Kubernetes service account token projection and Azure AD federated credentials to give pods fine-grained access to Azure resources — without storing any secrets.

The flow is:

1. A Kubernetes ServiceAccount is annotated with an Azure client ID
2. AKS projects a signed token into the pod
3. The pod exchanges this token for an Azure AD token
4. The Azure AD token is used to access Azure resources (Key Vault, Storage, etc.)

Here's how the module configures it:

```hcl
module "aks" {
  source = "github.com/kogunlowo123/terraform-azure-aks"

  # ... other config ...

  # Enable workload identity
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}

# Create a managed identity for your application
resource "azurerm_user_assigned_identity" "app" {
  name                = "app-workload-identity"
  resource_group_name = azurerm_resource_group.aks.name
  location            = "westeurope"
}

# Federate the identity with the Kubernetes service account
resource "azurerm_federated_identity_credential" "app" {
  name                = "app-federated-credential"
  resource_group_name = azurerm_resource_group.aks.name
  parent_id           = azurerm_user_assigned_identity.app.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:production:app-service-account"
}

# Grant the identity access to Key Vault
resource "azurerm_key_vault_access_policy" "app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.app.principal_id

  secret_permissions = ["Get", "List"]
}
```

On the Kubernetes side:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: production
  annotations:
    azure.workload.identity/client-id: "<managed-identity-client-id>"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
  namespace: production
spec:
  template:
    metadata:
      labels:
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: app-service-account
      containers:
        - name: app
          image: myregistry.azurecr.io/backend-api:v1.2.0
```

The `azure.workload.identity/use: "true"` label tells the admission webhook to inject the necessary environment variables and volume mounts. Your application code uses the standard Azure SDK — no code changes needed.

## Node Pool Strategy

A single node pool is almost never sufficient for production. Different workloads have different resource profiles, scaling characteristics, and isolation requirements.

```hcl
module "aks" {
  source = "github.com/kogunlowo123/terraform-azure-aks"

  # ... other config ...

  # System node pool (runs kube-system, CoreDNS, etc.)
  system_node_pool = {
    name                = "system"
    vm_size             = "Standard_D4s_v5"
    node_count          = 3
    min_count           = 3
    max_count           = 5
    enable_auto_scaling = true
    os_disk_size_gb     = 128
    os_disk_type        = "Managed"
    max_pods            = 50

    node_labels = {
      "nodepool-type" = "system"
      "environment"   = "production"
    }

    node_taints = ["CriticalAddonsOnly=true:NoSchedule"]
  }

  # Application node pools
  user_node_pools = {
    general = {
      name                = "general"
      vm_size             = "Standard_D8s_v5"
      min_count           = 3
      max_count           = 20
      enable_auto_scaling = true
      os_disk_size_gb     = 256
      os_disk_type        = "Ephemeral"
      max_pods            = 60

      node_labels = {
        "workload-type" = "general"
      }
    }

    compute = {
      name                = "compute"
      vm_size             = "Standard_F16s_v2"
      min_count           = 0
      max_count           = 10
      enable_auto_scaling = true
      os_disk_size_gb     = 128
      os_disk_type        = "Ephemeral"
      max_pods            = 30

      node_labels = {
        "workload-type" = "compute-intensive"
      }

      node_taints = ["workload=compute:NoSchedule"]
    }

    memory = {
      name                = "memory"
      vm_size             = "Standard_E8s_v5"
      min_count           = 0
      max_count           = 8
      enable_auto_scaling = true
      os_disk_size_gb     = 128
      os_disk_type        = "Ephemeral"
      max_pods            = 30

      node_labels = {
        "workload-type" = "memory-intensive"
      }

      node_taints = ["workload=memory:NoSchedule"]
    }
  }
}
```

Key decisions here:

- **System node pool** is tainted with `CriticalAddonsOnly` so only system components schedule there. This prevents application pods from disrupting CoreDNS or the metrics pipeline.
- **Ephemeral OS disks** for user node pools. They're faster and cheaper since they use the VM's local SSD. System pools use managed disks for durability.
- **Scale-to-zero** on specialized pools (`min_count = 0`). If no compute-intensive workloads are running, the nodes spin down entirely.
- **Separate taints** for specialized pools force workloads to explicitly opt in via tolerations.

## Microsoft Defender for Containers

Defender for Containers provides runtime threat detection, vulnerability scanning for container images, and security posture assessments. Enabling it through Terraform:

```hcl
module "aks" {
  source = "github.com/kogunlowo123/terraform-azure-aks"

  # ... other config ...

  microsoft_defender_enabled = true

  # Defender log analytics workspace
  defender_log_analytics_workspace_id = azurerm_log_analytics_workspace.security.id
}

resource "azurerm_log_analytics_workspace" "security" {
  name                = "law-aks-security"
  location            = "westeurope"
  resource_group_name = azurerm_resource_group.aks.name
  sku                 = "PerGB2018"
  retention_in_days   = 90
}
```

What Defender catches in practice:

- Containers running as root
- Crypto mining processes
- Known malicious IP connections
- Privileged container creation
- SSH server execution within a container
- Suspicious binary execution

It's not a replacement for proper security hygiene, but it's an excellent safety net.

## Additional Hardening

The module includes several other enterprise-grade configurations:

### Azure Policy for AKS

```hcl
azure_policy_enabled = true
```

This deploys the Azure Policy add-on, which can enforce policies like "no privileged containers" or "all images must come from approved registries" at the admission controller level.

### Private Cluster

```hcl
private_cluster_enabled           = true
private_cluster_public_fqdn_enabled = false
private_dns_zone_id               = azurerm_private_dns_zone.aks.id
```

A private cluster keeps the API server endpoint off the public internet entirely. All access goes through a private endpoint in your VNet.

### Key Vault Integration for Secrets

```hcl
key_vault_secrets_provider_enabled = true
key_vault_secrets_rotation_enabled = true
key_vault_secrets_rotation_interval = "2m"
```

This mounts Azure Key Vault secrets as volumes in your pods, with automatic rotation. No more manually syncing secrets into Kubernetes.

## Monitoring and Observability

```hcl
module "aks" {
  source = "github.com/kogunlowo123/terraform-azure-aks"

  # ... other config ...

  # Azure Monitor / Container Insights
  oms_agent_enabled                    = true
  log_analytics_workspace_id           = azurerm_log_analytics_workspace.aks.id

  # Prometheus metrics (managed)
  monitor_metrics_enabled = true

  # Diagnostic settings
  diagnostic_settings = {
    kube_apiserver        = true
    kube_controller_manager = true
    kube_scheduler        = true
    kube_audit            = true
    kube_audit_admin      = true
    cluster_autoscaler    = true
    guard                 = true
  }
}
```

Enable `kube_audit` logs from day one. When a security incident happens, you'll want to know exactly which service account created that suspicious pod.

## Deployment Workflow

Here's the order I follow for a greenfield deployment:

1. **Deploy the VNet** using [terraform-azure-virtual-network](https://github.com/kogunlowo123/terraform-azure-virtual-network)
2. **Deploy the AKS cluster** using this module
3. **Configure workload identities** for each application
4. **Apply Cilium network policies** progressively
5. **Enable Defender and Azure Policy** in audit mode first, then enforce

```bash
# Initialize and apply in sequence
cd infrastructure/vnet
terraform init && terraform apply

cd ../aks
terraform init && terraform apply

# Verify the cluster
az aks get-credentials --resource-group rg-aks-prod --name prod-aks-westeurope
kubectl get nodes
kubectl get pods -n kube-system
```

## Common Pitfalls

1. **Subnet sizing.** With Azure CNI Overlay, you only need IPs for nodes (not pods), but a `/24` subnet still limits you to ~250 nodes. Plan for growth.

2. **Kubernetes version pinning.** AKS auto-upgrades by default in some configurations. Pin your version and control upgrades through Terraform.

3. **Cilium and Windows nodes.** Cilium doesn't support Windows node pools. If you need Windows containers, use Azure CNI without Cilium for those pools.

4. **Workload Identity propagation delay.** After creating a federated credential, it can take 1-2 minutes for the token exchange to work. Build this into your CI/CD pipelines.

5. **Defender costs.** Microsoft Defender for Containers costs approximately $7/vCPU/month. On a cluster with 100 vCPUs, that's $700/month. Budget accordingly.

## Conclusion

An enterprise AKS cluster is more than `az aks create`. It requires thoughtful decisions about networking, identity, security, and observability — all of which should be codified in Terraform rather than configured manually through the portal.

The full module with all configurations discussed here is available at:

- [terraform-azure-aks](https://github.com/kogunlowo123/terraform-azure-aks) — Enterprise AKS module with Cilium, Workload Identity, and Defender
- [terraform-azure-virtual-network](https://github.com/kogunlowo123/terraform-azure-virtual-network) — Companion VNet module

Browse more infrastructure modules at [github.com/kogunlowo123](https://github.com/kogunlowo123).

---

*Running AKS in production? I'd love to hear about your node pool strategy or any Cilium gotchas you've encountered. Let me know in the comments.*