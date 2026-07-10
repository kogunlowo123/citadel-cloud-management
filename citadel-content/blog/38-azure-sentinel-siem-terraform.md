# Azure Sentinel SIEM with Terraform: Cloud-Native Security Operations

**Pillar:** Azure Infrastructure
**SEO Target:** azure sentinel terraform siem security operations analytics rules
**Word Count:** ~1600

Azure Sentinel (now Microsoft Sentinel) is a cloud-native SIEM/SOAR. It ingests signals from Azure, M365, AWS, GCP, and third-party sources, applies analytics rules, and triggers automated playbooks. This guide deploys Sentinel with scheduled analytics rules, data connectors, and automated incident response using Terraform.

## Log Analytics Workspace (Sentinel Foundation)

```hcl
resource "azurerm_log_analytics_workspace" "sentinel" {
  name                = "${var.prefix}-sentinel-law"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 90

  daily_quota_gb = var.environment == "prod" ? -1 : 10

  tags = var.tags
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "main" {
  workspace_id = azurerm_log_analytics_workspace.sentinel.id
}
```

## Data Connectors

```hcl
resource "azurerm_sentinel_data_connector_azure_active_directory" "aad" {
  name                       = "aad-connector"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.main.workspace_id
  tenant_id                  = var.tenant_id
}

resource "azurerm_sentinel_data_connector_azure_security_center" "asc" {
  name                       = "asc-connector"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.main.workspace_id
  subscription_id            = var.subscription_id
}

resource "azurerm_sentinel_data_connector_microsoft_defender_advanced_threat_protection" "mde" {
  name                       = "mde-connector"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.main.workspace_id
  tenant_id                  = var.tenant_id
}

resource "azurerm_sentinel_data_connector_office_365" "o365" {
  name                       = "o365-connector"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.main.workspace_id
  tenant_id                  = var.tenant_id

  exchange   = true
  sharepoint = true
  teams      = true
}
```

## Scheduled Analytics Rules

```hcl
resource "azurerm_sentinel_alert_rule_scheduled" "impossible_travel" {
  name                       = "impossible-travel"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.main.workspace_id
  display_name               = "Impossible Travel: AAD Sign-ins from Multiple Countries"
  severity                   = "Medium"
  enabled                    = true

  query = <<-KQL
    let timeframe = 4h;
    let threshold_km = 500;
    SigninLogs
    | where TimeGenerated > ago(timeframe)
    | where ResultType == 0
    | extend City = tostring(LocationDetails.city)
    | extend CountryOrRegion = tostring(LocationDetails.countryOrRegion)
    | extend Latitude = toreal(LocationDetails.geoCoordinates.latitude)
    | extend Longitude = toreal(LocationDetails.geoCoordinates.longitude)
    | summarize
        make_list(CountryOrRegion) by UserPrincipalName
    | where array_length(set_distinct(CountryOrRegion_list)) > 1
    | project UserPrincipalName, Countries = set_distinct(CountryOrRegion_list)
  KQL

  query_frequency = "PT4H"
  query_period    = "PT4H"

  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  incident_configuration {
    create_incident = true
    grouping {
      enabled                 = true
      lookback_duration       = "PT5H"
      reopen_closed_incidents = false
      entity_matching_method  = "Selected"
      group_by_entities       = ["Account"]
    }
  }

  entity_mapping {
    entity_type = "Account"
    field_mapping {
      identifier  = "FullName"
      column_name = "UserPrincipalName"
    }
  }

  tactics    = ["InitialAccess"]
  techniques = ["T1078"]
}

resource "azurerm_sentinel_alert_rule_scheduled" "privilege_escalation" {
  name                       = "privilege-escalation"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.main.workspace_id
  display_name               = "Privilege Escalation: New Global Admin"
  severity                   = "High"
  enabled                    = true

  query = <<-KQL
    AuditLogs
    | where TimeGenerated > ago(1h)
    | where OperationName == "Add member to role"
    | extend TargetRole = tostring(TargetResources[0].displayName)
    | where TargetRole == "Global Administrator"
    | extend Actor = tostring(InitiatedBy.user.userPrincipalName)
    | extend Target = tostring(TargetResources[0].userPrincipalName)
    | project TimeGenerated, Actor, Target, TargetRole, CorrelationId
  KQL

  query_frequency = "PT1H"
  query_period    = "PT1H"
  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  incident_configuration {
    create_incident = true
    grouping {
      enabled = false
    }
  }

  entity_mapping {
    entity_type = "Account"
    field_mapping {
      identifier  = "FullName"
      column_name = "Actor"
    }
  }

  tactics    = ["PrivilegeEscalation"]
  techniques = ["T1078.004"]
}
```

## Automation Playbook (Logic App)

```hcl
resource "azurerm_logic_app_workflow" "disable_compromised_user" {
  name                = "${var.prefix}-disable-user-playbook"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "playbook_sentinel_responder" {
  scope                = azurerm_log_analytics_workspace.sentinel.id
  role_definition_name = "Microsoft Sentinel Responder"
  principal_id         = azurerm_logic_app_workflow.disable_compromised_user.identity[0].principal_id
}

resource "azurerm_sentinel_automation_rule" "disable_on_high" {
  name                       = "disable-user-on-high-severity"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.main.workspace_id
  display_name               = "Disable Account on High Severity Incident"
  order                      = 1
  enabled                    = true

  condition {
    property  = "IncidentSeverity"
    operator  = "Equals"
    values    = ["High"]
  }

  action_playbook {
    logic_app_id            = azurerm_logic_app_workflow.disable_compromised_user.id
    tenant_id               = var.tenant_id
    order                   = 1
  }
}
```

## Watchlist for Known Bad IPs

```hcl
resource "azurerm_sentinel_watchlist" "threat_ips" {
  name                       = "ThreatIntelIPs"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.main.workspace_id
  display_name               = "Known Threat Intel IP Addresses"
  item_search_key            = "IPAddress"
  description                = "IP addresses from threat intelligence feeds"
}
```

## Production Checklist

- [ ] Log Analytics workspace with 90-day retention (adjust for compliance)
- [ ] Data connectors: AAD, ASC, MDE, O365 all enabled
- [ ] Scheduled analytics rules with KQL for impossible travel + privilege escalation
- [ ] Entity mapping on all rules (Account, IP, Host) for incident correlation
- [ ] MITRE ATT&CK tactics and techniques tagged on each rule
- [ ] Automation rule: disable account on High severity incidents
- [ ] Watchlist for threat intel IP addresses
- [ ] Incident grouping with 5h lookback to reduce alert noise
- [ ] Daily quota on non-production workspaces (controls cost)

Sentinel's value compounds over time — the more data sources connected, the better the correlation. Start with AAD and ASC, add M365 and Defender, then third-party sources as you mature.
