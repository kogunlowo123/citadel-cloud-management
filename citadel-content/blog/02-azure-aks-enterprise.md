# Enterprise Azure AKS with Terraform: AAD Integration, RBAC, and Private Clusters

**Pillar:** Azure Infrastructure
**SEO Target:** "azure aks terraform enterprise", "terraform aks private cluster aad"
**Word Count:** ~2,200

---

Running AKS in a dev environment and running it in an enterprise environment are two completely different problems. The difference isn't Kubernetes itself — it's everything around it: identity, networking, compliance, cost controls, and operational procedures.

This guide covers the patterns I use for enterprise AKS deployments using Terraform, built around the [terraform-azure-aks](https://github.com/Citadel-Cloud-Management/terraform-azure-aks) module.

## Why Private Clusters Matter

In an enterprise, your AKS API server should never be publicly reachable. A private cluster ensures that the Kubernetes API is only accessible from within your virtual network or over a private peering.

```hcl
module "aks" {
  source = "github.com/Citadel-Cloud-Management/terraform-azure-aks"

  cluster_name        = "enterprise-aks"
  resource_group_name = azurerm_resource_group.main.name
  location            = "eastus2"
  kubernetes_version  = "1.29"

  # Private cluster - API server not internet-accessible
  private_cluster_enabled             = true
  private_dns_zone_id                 = azurerm_private_dns_zone.aks.id
  api_server_authorized_ip_ranges     = null  # Null required for private clusters

  # Node pool sizing
  default_node_pool = {
    name                = "system"
    node_count          = 3
    vm_size             = "Standard_D4s_v3"
    availability_zones  = ["1", "2", "3"]
    os_disk_size_gb     = 128
    max_pods            = 30
  }
}
```

## Azure AD Integration with Managed Identity

The old way (service principal credentials in Kubernetes secrets) is gone. Use managed identities and Azure AD-backed RBAC:

```hcl
# AAD-integrated RBAC
azure_active_directory_role_based_access_control = {
  managed                = true
  azure_rbac_enabled     = true
  tenant_id              = data.azurerm_client_config.current.tenant_id
  admin_group_object_ids = [var.aks_admin_group_id]
}

# Kubelet identity for node pool
kubelet_identity = {
  client_id                 = azurerm_user_assigned_identity.kubelet.client_id
  object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
  user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
}
```

With this setup, cluster access is controlled through Azure AD groups — no kubeconfig credentials to rotate, no service account tokens to manage.

## Multi-Node Pool Architecture

Separate node pools by workload type:

```hcl
node_pools = {
  system = {
    node_count    = 3
    vm_size       = "Standard_D4s_v3"
    node_taints   = ["CriticalAddonsOnly=true:NoSchedule"]
    node_labels   = { role = "system" }
  }
  application = {
    node_count    = 5
    vm_size       = "Standard_D8s_v3"
    enable_auto_scaling = true
    min_count     = 2
    max_count     = 20
  }
  gpu = {
    node_count    = 0
    vm_size       = "Standard_NC6s_v3"
    enable_auto_scaling = true
    min_count     = 0
    max_count     = 5
    node_taints   = ["nvidia.com/gpu=present:NoSchedule"]
  }
}
```

## Network Policy with Azure CNI

CNI gives every pod a real VNet IP — critical for enterprise networking:

```hcl
network_profile = {
  network_plugin     = "azure"
  network_policy     = "calico"
  service_cidr       = "172.16.0.0/16"
  dns_service_ip     = "172.16.0.10"
  load_balancer_sku  = "standard"
  outbound_type      = "userDefinedRouting"  # Route all egress through Azure Firewall
}
```

With `outbound_type = "userDefinedRouting"`, all cluster egress goes through your Azure Firewall — no pods can call home without an explicit allow rule.

## Container Registry Integration

Pull images from ACR without secrets:

```hcl
# Attach ACR to AKS via managed identity
resource "azurerm_role_assignment" "aks_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity[0].object_id
}
```

## Monitoring with Azure Monitor

```hcl
oms_agent = {
  enabled                    = true
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

microsoft_defender = {
  enabled                    = true
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}
```

Enable Defender for Containers in production — it detects anomalous container behavior and vulnerable images at runtime.

## Production Checklist

- [ ] Private cluster enabled with private DNS zone
- [ ] AAD integration with Azure RBAC (not legacy RBAC)
- [ ] System node pool tainted (`CriticalAddonsOnly`)
- [ ] Application node pool with cluster autoscaler
- [ ] Azure CNI with Calico network policy
- [ ] UDR egress through Azure Firewall
- [ ] ACR attached via managed identity
- [ ] Defender for Containers enabled
- [ ] Log Analytics workspace connected
- [ ] Maintenance windows configured

## Module

Full enterprise AKS module: [terraform-azure-aks](https://github.com/Citadel-Cloud-Management/terraform-azure-aks)
