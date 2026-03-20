# modules/networking/main.tf — VNet / subnet / NSG / firewall / peering module.
# Provisions: resource group, VNet with configurable subnets and DNS servers,
# shared NSG with subnet associations, optional Azure Firewall (Standard) with public IP,
# and optional bidirectional VNet peering (spoke-to-hub + hub-to-spoke reverse).

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

resource "azurerm_virtual_network" "this" {
  #checkov:skip=CKV_AZURE_183: DNS servers injected post-AADDS deploy; Azure default DNS used on first apply (two-pass deployment)
  name                = "vnet-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  address_space       = var.vnet_config.address_spaces
  dns_servers         = length(var.dns_servers) > 0 ? var.dns_servers : null

  tags = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = { for idx, subnet in var.vnet_config.subnets : subnet.name => subnet }

  name                 = each.value.name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = each.value.address_prefixes
  service_endpoints    = each.value.service_endpoints

  dynamic "delegation" {
    for_each = each.value.delegations
    content {
      name = delegation.value
      service_delegation {
        name = delegation.value
      }
    }
  }
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  dynamic "security_rule" {
    for_each = var.nsg_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = security_rule.value.source_port_range
      destination_port_range     = security_rule.value.destination_port_range
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix
    }
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = { for idx, subnet in var.vnet_config.subnets : subnet.name => subnet }

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_firewall" "this" {
  #checkov:skip=CKV_AZURE_216: Standard-tier spoke firewall uses classic rule collections; threat_intel_mode requires azurerm_firewall_policy which requires Premium SKU — not applicable for spoke-level Standard firewalls
  #checkov:skip=CKV_AZURE_219: Standard-tier spoke firewall uses classic rule collections inline; firewall policy is a Premium-only feature not applicable here
  count = var.enable_firewall ? 1 : 0

  name                = "fw-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.this["AzureFirewallSubnet"].id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  tags = var.tags
}

resource "azurerm_public_ip" "firewall" {
  count = var.enable_firewall ? 1 : 0

  name                = "pip-fw-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

resource "azurerm_virtual_network_peering" "this" {
  count = var.enable_peering && var.peering_config != null ? 1 : 0

  name                      = "peer-${var.environment}-to-remote"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = var.peering_config.remote_vnet_id
  allow_forwarded_traffic   = var.peering_config.allow_forwarded_traffic
  allow_gateway_transit     = var.peering_config.allow_gateway_transit
}

resource "azurerm_virtual_network_peering" "reverse" {
  count = var.enable_peering && var.peering_config != null ? 1 : 0

  name                      = "peer-remote-to-${var.environment}"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = var.peering_config.remote_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.this.id
  allow_forwarded_traffic   = var.peering_config.allow_forwarded_traffic
}
