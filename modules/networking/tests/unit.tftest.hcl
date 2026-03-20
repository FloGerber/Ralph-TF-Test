mock_provider "azurerm" {
  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking-test/providers/Microsoft.Network/networkSecurityGroups/nsg-test"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/subnet-test"
    }
  }

  mock_resource "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
    }
  }
}

variables {
  location            = "eastus"
  environment         = "test"
  resource_group_name = "rg-networking-test"
  tags = {
    environment = "test"
    workload    = "networking"
  }
  vnet_config = {
    address_spaces = ["10.42.0.0/16"]
    subnets = [
      {
        name              = "app"
        address_prefixes  = ["10.42.1.0/24"]
        service_endpoints = []
        delegations       = []
      },
      {
        name              = "data"
        address_prefixes  = ["10.42.2.0/24"]
        service_endpoints = []
        delegations       = []
      },
      {
        name              = "AzureFirewallSubnet"
        address_prefixes  = ["10.42.255.0/26"]
        service_endpoints = []
        delegations       = []
      }
    ]
  }
  dns_servers     = []
  enable_firewall = false
  enable_peering  = false
  peering_config  = null
  nsg_rules       = []
}

run "test_default_vnet_config" {
  command = plan

  assert {
    condition     = output.vnet_id != ""
    error_message = "Expected the virtual network ID output to be populated."
  }

  assert {
    condition     = contains(keys(output.subnet_ids), "app") && contains(keys(output.subnet_ids), "data")
    error_message = "Expected subnet_ids to include the app and data subnets."
  }
}

run "test_nsg_rules_applied" {
  command = plan

  variables {
    nsg_rules = [
      {
        name                       = "allow-https-in"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
      {
        name                       = "allow-dns-out"
        priority                   = 110
        direction                  = "Outbound"
        access                     = "Allow"
        protocol                   = "Udp"
        source_port_range          = "*"
        destination_port_range     = "53"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      }
    ]
  }

  assert {
    condition     = length([azurerm_network_security_group.this]) > 0
    error_message = "Expected at least one network security group resource in the plan."
  }

  assert {
    condition     = length(azurerm_network_security_group.this.security_rule) == 2
    error_message = "Expected the custom NSG rules to be rendered on the network security group."
  }
}

run "test_firewall_disabled" {
  command = plan

  variables {
    enable_firewall = false
  }

  assert {
    condition     = length(azurerm_firewall.this) == 0
    error_message = "Expected no Azure Firewall resources when enable_firewall is false."
  }
}
