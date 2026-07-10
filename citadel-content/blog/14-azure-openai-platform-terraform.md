# Azure OpenAI Platform with Terraform: Private Endpoints, APIM, and Cost Controls

**Pillar:** Azure Infrastructure / AI/ML Engineering
**SEO Target:** "azure openai terraform", "terraform azure openai private endpoint"
**Word Count:** ~1,800

---

Azure OpenAI is now the preferred way for enterprises to deploy GPT-4, GPT-4o, and DALL-E in a private, compliant environment. The service uses your Azure tenant, your VNet, and your logging — none of your data goes into model training.

Here's the Terraform architecture I use for production Azure OpenAI deployments.

## Architecture Overview

```
Clients (internal)
       │
       ▼
Azure API Management (APIM)
  - Rate limiting per team/product
  - Authentication (subscription keys or AAD)
  - Usage logging per consumer
       │
       ▼
Private Endpoint ──► Azure OpenAI Service
  - No public internet access
  - Traffic stays in your VNet
       │
       ▼
Azure Monitor + Log Analytics
  - Token consumption metrics
  - Cost allocation by team
  - Latency and error tracking
```

## The Terraform Module

```hcl
module "azure_openai" {
  source = "github.com/Citadel-Cloud-Management/terraform-azure-openai-platform"

  resource_group_name = azurerm_resource_group.ai.name
  location            = "eastus"  # Not all models available in all regions

  # OpenAI Account
  openai_account_name = "citadel-openai-prod"
  sku_name            = "S0"

  # Model deployments
  model_deployments = {
    "gpt-4o" = {
      model_name    = "gpt-4o"
      model_version = "2024-11-20"
      capacity      = 50  # 50K tokens per minute
      scale_type    = "Standard"
    }
    "gpt-4o-mini" = {
      model_name    = "gpt-4o-mini"
      model_version = "2024-07-18"
      capacity      = 200
      scale_type    = "Standard"
    }
    "text-embedding-3-large" = {
      model_name    = "text-embedding-3-large"
      model_version = "1"
      capacity      = 120
      scale_type    = "Standard"
    }
  }

  # Private networking
  enable_public_network_access = false
  private_endpoint_subnet_id   = azurerm_subnet.private_endpoints.id
  private_dns_zone_id          = azurerm_private_dns_zone.openai.id

  # APIM integration
  enable_apim            = true
  apim_resource_group    = azurerm_resource_group.apim.name
  apim_name              = azurerm_api_management.main.name

  tags = local.tags
}
```

## Private Endpoint Configuration

Public access disabled means all traffic flows through a private endpoint in your VNet:

```hcl
resource "azurerm_private_endpoint" "openai" {
  name                = "pe-openai-prod"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-openai"
    private_connection_resource_id = azurerm_cognitive_account.openai.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "openai-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.openai.id]
  }
}

# DNS zone for private resolution
resource "azurerm_private_dns_zone" "openai" {
  name                = "privatelink.openai.azure.com"
  resource_group_name = var.resource_group_name
}

# Link DNS zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "openai" {
  name                  = "openai-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.openai.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
}
```

With this, `citadel-openai-prod.openai.azure.com` resolves to a private IP inside your VNet — no traffic leaves your network perimeter.

## APIM Rate Limiting per Team

APIM lets you issue different subscription keys to different teams with different rate limits:

```xml
<!-- APIM Policy for Team A (Engineering) -->
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token
      tenant-id="{{tenant-id}}"
      header-name="Authorization"
      failed-validation-httpcode="401" />
    <rate-limit calls="1000" renewal-period="60" />
    <quota calls="100000" renewal-period="86400" />
    <set-header name="api-key" exists-action="override">
      <value>{{openai-api-key}}</value>
    </set-header>
  </inbound>
</policies>
```

Teams authenticate to APIM with their Azure AD identity. APIM handles key rotation — teams never see the actual OpenAI API key.

## Content Safety

Always enable Azure Content Safety in production:

```hcl
resource "azurerm_cognitive_account" "content_safety" {
  name                = "content-safety-prod"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "ContentSafety"
  sku_name            = "F0"  # Free tier for <5K calls/month
}
```

Route all user-generated content through Content Safety before passing to the LLM. It detects violence, hate speech, self-harm, and sexual content with low latency.

## Cost Monitoring

Azure OpenAI costs can surprise you. Track token consumption proactively:

```hcl
resource "azurerm_monitor_metric_alert" "openai_token_usage" {
  name                = "openai-high-token-usage"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_cognitive_account.openai.id]
  description         = "Alert when token usage exceeds 80% of capacity"

  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "TotalTokenCalls"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 80000  # 80% of 100K capacity
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }
}
```

Set budget alerts in Azure Cost Management for the resource group containing your OpenAI resources.

## Module

[terraform-azure-openai-platform](https://github.com/Citadel-Cloud-Management/terraform-azure-openai-platform) — complete Azure OpenAI deployment with APIM, private endpoints, content safety, and monitoring.
