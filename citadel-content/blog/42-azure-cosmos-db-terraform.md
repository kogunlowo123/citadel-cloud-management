# Azure Cosmos DB with Terraform: Global NoSQL at Scale

**Pillar:** Azure Infrastructure
**SEO Target:** azure cosmos db terraform global nosql multi-region consistency
**Word Count:** ~1500

Azure Cosmos DB is Microsoft's globally distributed, multi-model NoSQL database. Sub-10ms reads and writes with five consistency models, automatic multi-region replication, and serverless or autoscale provisioning. This guide deploys Cosmos DB with the SQL API, multi-region writes, and analytical store using Terraform.

## Cosmos DB Account

```hcl
resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.prefix}-cosmos"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = true
  }

  geo_location {
    location          = var.secondary_location
    failover_priority = 1
    zone_redundant    = true
  }

  enable_multiple_write_locations = true
  enable_automatic_failover       = true

  is_virtual_network_filter_enabled = true

  virtual_network_rule {
    id = azurerm_subnet.app.id
  }

  backup {
    type                = "Continuous"
    tier                = "Continuous30Days"
  }

  analytical_storage_enabled = true

  analytical_storage {
    schema_type = "WellDefined"
  }

  tags = var.tags
}
```

## Database and Container with Autoscale

```hcl
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = var.database_name
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_sql_container" "orders" {
  name                  = "orders"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.main.name
  partition_key_path    = "/customerId"
  partition_key_version = 2
  analytical_storage_ttl = -1

  autoscale_settings {
    max_throughput = 4000
  }

  indexing_policy {
    indexing_mode = "consistent"

    included_path { path = "/*" }
    excluded_path { path = "/largePayload/?" }
    excluded_path { path = "/_etag/?" }

    composite_index {
      index { path = "/customerId";  order = "Ascending" }
      index { path = "/orderStatus"; order = "Ascending" }
    }
  }

  unique_key {
    paths = ["/orderId"]
  }

  conflict_resolution_policy {
    mode                          = "LastWriterWins"
    conflict_resolution_path      = "/_ts"
  }
}
```

## Private Endpoint

```hcl
resource "azurerm_private_endpoint" "cosmos" {
  name                = "${var.prefix}-cosmos-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "cosmos-connection"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "cosmos-dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.cosmos.id]
  }
}
```

## Production Checklist

- [ ] Multi-region with multiple write locations (active-active)
- [ ] Session consistency (sweet spot: strong reads within a session, eventual cross-region)
- [ ] Continuous backup 30-day retention (point-in-time restore)
- [ ] Analytical store enabled with Synapse Link (zero-ETL analytics)
- [ ] Partition key design: high cardinality, even distribution (/customerId)
- [ ] Composite indexes for multi-field filter queries
- [ ] Autoscale throughput (4000 RU/s max — scales to demand, not fixed allocation)
- [ ] Private endpoint — no public network access
- [ ] Unique keys for business-level deduplication (/orderId)

Cosmos DB's multiple write locations give you zero-RPO active-active globally. The Session consistency model covers 90% of use cases — it reads your own writes while accepting eventual consistency elsewhere.

## About This Guide

This guide is part of the Citadel Cloud Management content series covering AWS, Azure, GCP, DevSecOps, MCP Servers, and Cloud Careers. Follow our GitHub: https://github.com/kogunlowo123/citadel-cloud-management
