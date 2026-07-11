---
title: "Azure OpenAI Service with Terraform: Enterprise AI Platform"
published: true
description: "Deploy Azure OpenAI with Terraform: private endpoint, Key Vault secrets, RBAC, GPT-4o + text-embedding-3 deployments, and content filtering — production-ready."
tags: azure, terraform, ai, cloud
series: "Citadel Cloud Management: 100 Free Terraform Guides"
canonical_url: https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/14-azure-openai-platform-terraform.md
cover_image: ""
---

Azure OpenAI gives enterprises access to GPT-4o, GPT-4, and text-embedding models inside their own Azure tenant, with their own VNet, and their own compliance boundary. None of your data goes into model training. All traffic stays inside your network.

Here is the Terraform architecture I use for production Azure OpenAI deployments — private endpoint, Key Vault secrets, RBAC, and content filtering included.

## Model Comparison

Not all models are available in all regions. Pick the right model for each workload before writing Terraform.

| Model | Best For | Max Tokens | Relative Cost |
|-------|----------|-----------|---------------|
| GPT-4o | Complex reasoning, code generation, agentic tasks | 128,000 | High |
| GPT-4o mini | High-volume classification, summarization, chat | 128,000 | Low |
| GPT-4 | Legacy workloads requiring GPT-4 compatibility | 8,192 / 32,768 | High |
| text-embedding-3-large | High-accuracy semantic search, RAG pipelines | 8,191 | Low |
| text-embedding-3-small | Fast embedding at lower cost | 8,191 | Very low |
| DALL-E 3 | Image generation from text prompts | N/A | Per image |

For most new deployments: GPT-4o for complex tasks, GPT-4o mini for volume, text-embedding-3-large for RAG.

## Core Cognitive Account

```hcl
resource "azurerm_cognitive_account" "openai" {
  name                = "citadel-openai-prod"
  location            = var.location  # Not all models in all regions
  resource_group_name = azurerm_resource_group.ai.name
  kind                = "OpenAI"
  sku_name            = "S0"

  # Disable public internet access — traffic via private endpoint only
  public_network_access_enabled = false

  # System-assigned identity for Key Vault and Azure Monitor integration
  identity {
    type = "SystemAssigned"
  }

  # Content filtering is on by default; configure per-deployment below
  custom_subdomain_name = "citadel-openai-prod"

  network_acls {
    default_action = "Deny"
    # No IP rules — all access through private endpoint
  }

  tags = var.tags
}
```

## Model Deployments

Each model family is a separate `azurerm_cognitive_deployment` resource. Capacity is set in thousands of tokens per minute (TPM).

```hcl
resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-11-20"
  }

  scale {
    type     = "Standard"
    capacity = 50  # 50K tokens per minute
  }
}

resource "azurerm_cognitive_deployment" "gpt4o_mini" {
  name                 = "gpt-4o-mini"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o-mini"
    version = "2024-07-18"
  }

  scale {
    type     = "Standard"
    capacity = 200  # 200K tokens per minute — higher volume
  }
}

resource "azurerm_cognitive_deployment" "embeddings" {
  name                 = "text-embedding-3-large"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "text-embedding-3-large"
    version = "1"
  }

  scale {
    type     = "Standard"
    capacity = 120
  }
}
```

## Private Endpoint

All traffic to Azure OpenAI flows through a private endpoint inside your VNet. No public DNS resolution, no internet exposure.

```hcl
resource "azurerm_private_endpoint" "openai" {
  name                = "pe-openai-prod"
  location            = var.location
  resource_group_name = azurerm_resource_group.ai.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-openai"
    private_connection_resource_id = azurerm_cognitive_account.openai.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "openai-dns-zone-group"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.openai.id
    ]
  }
}

resource "azurerm_private_dns_zone" "openai" {
  name                = "privatelink.openai.azure.com"
  resource_group_name = azurerm_resource_group.ai.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "openai" {
  name                  = "openai-dns-link"
  resource_group_name   = azurerm_resource_group.ai.name
  private_dns_zone_name = azurerm_private_dns_zone.openai.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
}
```

## Key Vault Integration

Store the Azure OpenAI endpoint and API key in Key Vault. Applications retrieve the secret at runtime — no credentials in environment variables or app config files.

```hcl
resource "azurerm_key_vault" "ai_secrets" {
  name                = "kv-citadel-ai-prod"
  location            = var.location
  resource_group_name = azurerm_resource_group.ai.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Soft delete and purge protection required for production
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # Disable public access
  public_network_access_enabled = false

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }
}

# Store the OpenAI endpoint
resource "azurerm_key_vault_secret" "openai_endpoint" {
  name         = "openai-endpoint"
  value        = azurerm_cognitive_account.openai.endpoint
  key_vault_id = azurerm_key_vault.ai_secrets.id

  depends_on = [azurerm_key_vault_access_policy.terraform_deploy]
}

# Store the OpenAI primary key
resource "azurerm_key_vault_secret" "openai_key" {
  name         = "openai-primary-key"
  value        = azurerm_cognitive_account.openai.primary_access_key
  key_vault_id = azurerm_key_vault.ai_secrets.id

  depends_on = [azurerm_key_vault_access_policy.terraform_deploy]
}
```

## RBAC Assignment

Prefer Azure RBAC over access keys where possible. Applications running on Azure services (App Service, AKS, Functions) can use managed identities with the `Cognitive Services OpenAI User` role.

```hcl
# Role for applications that call the OpenAI API
resource "azurerm_role_assignment" "openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# Role for administrators who manage deployments and configuration
resource "azurerm_role_assignment" "openai_contributor" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI Contributor"
  principal_id         = var.ai_platform_team_object_id
}

# Grant the OpenAI system identity access to Key Vault secrets
resource "azurerm_key_vault_access_policy" "openai_identity" {
  key_vault_id = azurerm_key_vault.ai_secrets.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_cognitive_account.openai.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}
```

## Content Filtering

Azure OpenAI applies default content filtering to all deployments. For enterprise workloads with controlled user populations, you may request a modified policy through the Azure portal — but the default policy is appropriate for most deployments and cannot be disabled via Terraform directly.

Monitor content filter events through Azure Monitor:

```hcl
resource "azurerm_monitor_diagnostic_setting" "openai" {
  name                       = "openai-diagnostics"
  target_resource_id         = azurerm_cognitive_account.openai.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "Audit"
  }

  enabled_log {
    category = "RequestResponse"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
```

## Key Outputs

```hcl
output "openai_endpoint" {
  value     = azurerm_cognitive_account.openai.endpoint
  sensitive = true
}

output "openai_resource_id" {
  value = azurerm_cognitive_account.openai.id
}

output "gpt4o_deployment_name" {
  value = azurerm_cognitive_deployment.gpt4o.name
}

output "embedding_deployment_name" {
  value = azurerm_cognitive_deployment.embeddings.name
}

output "private_endpoint_ip" {
  value = azurerm_private_endpoint.openai.private_service_connection[0].private_ip_address
}
```

## Production Checklist

Before this platform handles production AI workloads:

- [ ] `public_network_access_enabled = false` on the cognitive account
- [ ] Private endpoint deployed in the correct subnet with DNS zone linked to the VNet
- [ ] `azurerm_private_dns_zone` set to `privatelink.openai.azure.com`
- [ ] Deployment region verified for model availability (GPT-4o not in all regions)
- [ ] TPM capacity sized for peak workload — request quota increase if needed
- [ ] API keys stored in Key Vault — not in app config, not in environment variables
- [ ] Applications use managed identity with `Cognitive Services OpenAI User` role where possible
- [ ] `soft_delete_retention_days = 90` and `purge_protection_enabled = true` on Key Vault
- [ ] Diagnostic settings sending logs to Log Analytics
- [ ] Cost alerts configured on the resource group for unexpected token spend
- [ ] Model version pinned in each `azurerm_cognitive_deployment` — avoid floating versions
- [ ] Deployment names match what application code expects — changes require app redeployment

## What You Get

A production Azure OpenAI platform built with Terraform gives you:

- **No public internet exposure** — all API calls flow through a private endpoint in your VNet
- **Credential-free access** — managed identity and RBAC replace API key distribution
- **Centralized secret management** — Key Vault holds the endpoint and key with audit logging
- **Full observability** — token consumption, latency, and content filter events in Log Analytics
- **Multiple model deployments** — GPT-4o for reasoning, GPT-4o mini for volume, text-embedding-3-large for RAG, all under one cognitive account

The full module with variables, outputs, and APIM integration is available at [Citadel Cloud Management](https://github.com/kogunlowo123/citadel-cloud-management/blob/main/citadel-content/blog/14-azure-openai-platform-terraform.md).
