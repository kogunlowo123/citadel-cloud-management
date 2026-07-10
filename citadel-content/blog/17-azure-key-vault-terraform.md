# Azure Key Vault with Terraform: Secrets, Certificates, and Keys Management

**Pillar:** Azure Infrastructure
**SEO Target:** azure key vault terraform enterprise
**Word Count:** ~1700

Azure Key Vault is the central secrets management service for Azure workloads. This guide covers deploying Key Vault with Terraform, integrating it with Azure Kubernetes Service, virtual machines, and Azure Functions, and enforcing RBAC over legacy access policies.

## Why Key Vault in Every Azure Landing Zone

Key Vault solves three problems simultaneously: secrets storage (connection strings, API keys), cryptographic key management (TDE keys, disk encryption), and certificate lifecycle management (auto-renewal via DigiCert or Let's Encrypt integration). Every production workload in Azure should read secrets from Key Vault rather than environment variables or config files.

## Terraform Resource

```hcl
resource "azurerm_key_vault" "main" {
  name                       = "${var.prefix}-kv-${var.environment}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "premium"
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # RBAC instead of legacy access policies
  enable_rbac_authorization = true

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }

  tags = var.tags
}
```

## RBAC Assignments

```hcl
# Application identity reads secrets
resource "azurerm_role_assignment" "app_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.app_managed_identity_id
}

# Ops team manages secrets
resource "azurerm_role_assignment" "ops_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.ops_group_id
}

# Security team audits only
resource "azurerm_role_assignment" "security_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Reader"
  principal_id         = var.security_group_id
}
```

## Storing Secrets

```hcl
resource "azurerm_key_vault_secret" "db_password" {
  name         = "database-password"
  value        = random_password.db.result
  key_vault_id = azurerm_key_vault.main.id

  content_type    = "text/plain"
  expiration_date = timeadd(timestamp(), "8760h") # 1 year

  tags = { managed_by = "terraform" }

  lifecycle {
    ignore_changes = [value]
  }
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
```

## RSA Key for Disk Encryption

```hcl
resource "azurerm_key_vault_key" "disk_encryption" {
  name         = "disk-encryption-key"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA-HSM"
  key_size     = 4096

  key_opts = [
    "decrypt", "encrypt",
    "sign", "unwrapKey",
    "verify", "wrapKey"
  ]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P365D"
    notify_before_expiry = "P29D"
  }
}

resource "azurerm_disk_encryption_set" "main" {
  name                = "${var.prefix}-des"
  location            = var.location
  resource_group_name = var.resource_group_name
  key_vault_key_id    = azurerm_key_vault_key.disk_encryption.id

  identity {
    type = "SystemAssigned"
  }
}
```

## Certificate Import and Auto-Renewal

```hcl
resource "azurerm_key_vault_certificate" "tls" {
  name         = "${var.prefix}-tls-cert"
  key_vault_id = azurerm_key_vault.main.id

  certificate_policy {
    issuer_parameters {
      name = "DigiCert"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]
      key_usage = [
        "digitalSignature", "keyEncipherment"
      ]
      subject            = "CN=${var.domain_name}"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = var.san_dns_names
      }
    }

    lifetime_action {
      action { action_type = "AutoRenew" }
      trigger { days_before_expiry = 30 }
    }
  }
}
```

## Private Endpoint for Zero-Trust Access

```hcl
resource "azurerm_private_endpoint" "kv" {
  name                = "${var.prefix}-kv-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.prefix}-kv-psc"
    private_connection_resource_id = azurerm_key_vault.main.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "kv-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }
}

resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv" {
  name                  = "${var.prefix}-kv-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
}
```

## Diagnostic Settings

```hcl
resource "azurerm_monitor_diagnostic_setting" "kv" {
  name               = "${var.prefix}-kv-diag"
  target_resource_id = azurerm_key_vault.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "AuditEvent" }
  enabled_log { category = "AzurePolicyEvaluationDetails" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
```

## AKS Integration via CSI Driver

```hcl
# Enable Secret Store CSI driver on AKS
resource "azurerm_kubernetes_cluster" "main" {
  # ... other config ...
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }
}

# SecretProviderClass (applied via kubectl or helm)
# apiVersion: secrets-store.csi.x-k8s.io/v1
# kind: SecretProviderClass
# spec:
#   provider: azure
#   parameters:
#     usePodIdentity: "false"
#     useVMManagedIdentity: "true"
#     userAssignedIdentityID: <managed-identity-client-id>
#     keyvaultName: <vault-name>
#     objects: |
#       array:
#         - |
#           objectName: database-password
#           objectType: secret
#     tenantId: <tenant-id>
```

## Outputs

```hcl
output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "disk_encryption_set_id" {
  value = azurerm_disk_encryption_set.main.id
}
```

## Security Checklist

- [ ] `purge_protection_enabled = true` — prevents permanent deletion
- [ ] `soft_delete_retention_days = 90` — maximum retention
- [ ] RBAC authorization over legacy access policies
- [ ] Network ACLs deny by default, allow only required subnets
- [ ] Private endpoint deployed — no public DNS resolution
- [ ] Diagnostic logs streaming to Log Analytics
- [ ] Key rotation policy configured for all cryptographic keys
- [ ] Certificate auto-renewal configured 30 days before expiry
- [ ] Managed Identity used by apps — no service principal passwords

Azure Key Vault with RBAC, private endpoints, and HSM-backed keys gives you a FIPS 140-2 Level 3 validated secrets store that satisfies SOC 2, ISO 27001, and PCI-DSS requirements without any additional tooling.
