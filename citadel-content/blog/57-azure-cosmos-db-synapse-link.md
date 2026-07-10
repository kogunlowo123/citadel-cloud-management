# Azure Cosmos DB Analytical Store: HTAP with Synapse Link

**Pillar:** Azure Infrastructure
**SEO Target:** azure cosmos db synapse link analytical store htap terraform power bi
**Word Count:** ~1400

Cosmos DB Analytical Store with Synapse Link enables zero-ETL analytics on operational data. No separate pipeline to run — analytical queries run against a column-store replica while OLTP continues unaffected.

## Cosmos DB with Analytical Store

```hcl
resource "azurerm_cosmosdb_account" "htap" {
  name                       = "${var.prefix}-htap"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  offer_type                 = "Standard"
  kind                       = "GlobalDocumentDB"
  analytical_storage_enabled = true

  analytical_storage {
    schema_type = "WellDefined"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  tags = var.tags
}

resource "azurerm_cosmosdb_sql_container" "events" {
  name                   = "events"
  resource_group_name    = var.resource_group_name
  account_name           = azurerm_cosmosdb_account.htap.name
  database_name          = azurerm_cosmosdb_sql_database.main.name
  partition_key_path     = "/eventType"
  analytical_storage_ttl = -1

  autoscale_settings {
    max_throughput = 4000
  }
}
```

## Synapse Link Workspace Connection

```hcl
resource "azurerm_synapse_linked_service" "cosmos" {
  name                 = "CosmosDbLinkedService"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  type                 = "CosmosDb"
  type_properties_json = jsonencode({
    connectionString = azurerm_cosmosdb_account.htap.connection_strings[0]
  })
}
```

## Production Checklist
- [ ] analytical_storage_enabled on Cosmos DB account
- [ ] analytical_storage_ttl = -1 (never expire analytical data)
- [ ] Synapse Link workspace connected to Cosmos DB
- [ ] Dedicated Synapse SQL pool for heavy queries (not serverless)
- [ ] Power BI Direct Query via Synapse for real-time dashboards
- [ ] Cost: analytical storage billed separately from transactional RU/s