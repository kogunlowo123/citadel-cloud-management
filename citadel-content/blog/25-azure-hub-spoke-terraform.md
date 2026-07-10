# Azure Hub-Spoke Network Topology with Terraform

**Pillar:** Azure Infrastructure
**SEO Target:** azure hub spoke network terraform enterprise
**Word Count:** ~1700

The hub-spoke network topology is the recommended Azure enterprise network architecture. A central hub VNet hosts shared services (firewall, VPN, DNS, Bastion), and spoke VNets connect to it via peering. All egress flows through the hub's Azure Firewall — giving you centralized visibility and control over all traffic.

## Architecture Overview

```
Hub VNet (10.0.0.0/16)
├── AzureFirewallSubnet (10.0.1.0/26) — Azure Firewall
├── GatewaySubnet (10.0.2.0/27) — VPN/ExpressRoute
├── AzureBastionSubnet (10.0.3.0/26) — Bastion Host
├── ManagementSubnet (10.0.4.0/24) — Jump servers, DNS

Spoke VNet 1 — Production (10.1.0.0/16)
├── AppSubnet (10.1.1.0/24)
└── DataSubnet (10.1.2.0/24)

Spoke VNet 2 — Development (10.2.0.0/16)
├── AppSubnet (10.2.1.0/24)
└── DataSubnet (10.2.2.0/24)
```

## Hub VNet

```hcl
resource "azurerm_virtual_network" "hub" {
  name                = "${var.prefix}-hub-vnet"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  address_space       = [var.hub_address_space]

  tags = var.tags
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 8, 1)]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 9, 4)]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 8, 3)]
}
```

## Azure Firewall

```hcl
resource "azurerm_public_ip" "firewall" {
  name                = "${var.prefix}-fw-pip"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_firewall_policy" "main" {
  name                = "${var.prefix}-fw-policy"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  sku                 = "Premium"

  threat_intelligence_mode = "Deny"

  intrusion_detection {
    mode = "Deny"
    signature_overrides {
      id    = "2008983"
      state = "Off"
    }
  }

  dns {
    proxy_enabled = true
    servers       = ["168.63.129.16"]
  }

  tags = var.tags
}

resource "azurerm_firewall" "main" {
  name                = "${var.prefix}-firewall"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  zones               = ["1", "2", "3"]
  firewall_policy_id  = azurerm_firewall_policy.main.id

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  tags = var.tags
}
```

## Firewall Policy Rules

```hcl
resource "azurerm_firewall_policy_rule_collection_group" "main" {
  name               = "production-rules"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 100

  # Allow outbound HTTPS to approved destinations
  application_rule_collection {
    name     = "allow-outbound-web"
    priority = 100
    action   = "Allow"

    rule {
      name = "allow-azure-services"
      source_addresses = ["10.0.0.0/8"]
      destination_fqdns = [
        "*.azure.com",
        "*.microsoft.com",
        "*.azure.net",
        "*.azureedge.net"
      ]
      protocols {
        port = "443"
        type = "Https"
      }
    }

    rule {
      name             = "allow-ubuntu-updates"
      source_addresses = ["10.0.0.0/8"]
      destination_fqdns = [
        "*.ubuntu.com",
        "*.snapcraft.io"
      ]
      protocols {
        port = "443"
        type = "Https"
      }
      protocols {
        port = "80"
        type = "Http"
      }
    }
  }

  # Allow spoke-to-spoke via hub
  network_rule_collection {
    name     = "allow-spoke-to-spoke"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "spoke1-to-spoke2"
      source_addresses      = [var.spoke1_address_space]
      destination_addresses = [var.spoke2_address_space]
      protocols             = ["TCP", "UDP"]
      destination_ports     = ["*"]
    }
  }

  # Deny everything else
  network_rule_collection {
    name     = "deny-all"
    priority = 65000
    action   = "Deny"

    rule {
      name                  = "deny-all"
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      protocols             = ["Any"]
      destination_ports     = ["*"]
    }
  }
}
```

## Spoke VNets and Peering

```hcl
module "spoke" {
  source   = "./modules/spoke"
  for_each = var.spokes

  name                = each.key
  location            = var.location
  resource_group_name = each.value.resource_group_name
  address_space       = each.value.address_space
  hub_vnet_id         = azurerm_virtual_network.hub.id
  hub_firewall_ip     = azurerm_firewall.main.ip_configuration[0].private_ip_address
  subnets             = each.value.subnets
  tags                = var.tags
}
```

## Spoke Module

```hcl
resource "azurerm_virtual_network" "spoke" {
  name                = "${var.name}-spoke-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

# Hub-to-spoke peering
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-${var.name}"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

# Spoke-to-hub peering
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "${var.name}-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = var.use_hub_gateway
}

# Route table — force all traffic through firewall
resource "azurerm_route_table" "spoke" {
  name                          = "${var.name}-rt"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  disable_bgp_route_propagation = true

  route {
    name                   = "to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.hub_firewall_ip
  }
}
```

## Azure Bastion

```hcl
resource "azurerm_public_ip" "bastion" {
  name                = "${var.prefix}-bastion-pip"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "main" {
  name                = "${var.prefix}-bastion"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  sku                 = "Standard"
  tunneling_enabled   = true
  file_copy_enabled   = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = var.tags
}
```

## Diagnostic Logging

```hcl
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name               = "${var.prefix}-fw-diag"
  target_resource_id = azurerm_firewall.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "AzureFirewallApplicationRule" }
  enabled_log { category = "AzureFirewallNetworkRule" }
  enabled_log { category = "AzureFirewallDnsProxy" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
```

## Variables

```hcl
variable "prefix" { type = string }
variable "location" { type = string }
variable "hub_resource_group_name" { type = string }
variable "hub_address_space" { type = string; default = "10.0.0.0/16" }
variable "spoke1_address_space" { type = string; default = "10.1.0.0/16" }
variable "spoke2_address_space" { type = string; default = "10.2.0.0/16" }
variable "log_analytics_workspace_id" { type = string }
variable "spokes" { type = map(any) }
variable "tags" { type = map(string); default = {} }
```

## Production Checklist

- [ ] Azure Firewall Premium SKU with IDPS enabled in Deny mode
- [ ] Threat intelligence mode set to Deny
- [ ] Zone-redundant Firewall (zones 1, 2, 3)
- [ ] All spoke subnets have route table forcing through firewall
- [ ] BGP propagation disabled on spoke route tables
- [ ] DNS Proxy enabled on Firewall Policy
- [ ] Bastion Standard SKU with tunneling for SSH/RDP
- [ ] Firewall logs streaming to Log Analytics
- [ ] AllMetrics enabled for capacity monitoring
- [ ] Gateway subnet reserved for ExpressRoute/VPN

This hub-spoke topology with Azure Firewall Premium satisfies enterprise networking requirements for financial services, healthcare, and government workloads running in Azure.
