# networking/hub-and-spoke/main.tf — Hub-and-spoke networking root module.
# Independent root configuration with its own backend state key (networking/hub-and-spoke).
# Provisions: Hub VNet (10.0.0.0/16) with GatewaySubnet, AzureFirewallSubnet, snet-aadds,
# management/frontend/backend subnets; Shared Spoke VNet (10.1.0.0/16); Dedicated Spoke VNet
# (10.2.0.0/16); Azure Firewall Premium with IDS Deny + Threat Intel Deny; NSGs for each VNet
# (Hub, Shared, Dedicated, AADDS) with explicit allow rules and deny-all defaults; bidirectional
# VNet peering (hub↔shared, hub↔dedicated); Private DNS Zones for private endpoints with hub
# VNet links. AADDS DNS IPs injected via aadds_dns_server_ips variable (two-pass deployment).
# Deploy with: tofu init -backend-config=../../backend.hcl && tofu apply

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "network_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "hub_vnet" {
  name                = "vnet-hub-${var.environment}"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  address_space       = var.hub_vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "hub_gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.0.0/27"]
}

resource "azurerm_subnet" "hub_firewall_subnet" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "hub_management_subnet" {
  name                 = "snet-management"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "hub_frontend_subnet" {
  name                 = "snet-frontend"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_subnet" "hub_backend_subnet" {
  name                 = "snet-backend"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.4.0/24"]
}

# ---------------------------------------------------------------------------
# AADDS Subnet (snet-aadds, 10.0.5.0/24)
# ---------------------------------------------------------------------------
# Azure AD Domain Services requires a dedicated subnet with an NSG that permits
# the management ports used by the Microsoft-managed domain controllers.
# Microsoft also injects its own service rules into this NSG automatically.
resource "azurerm_subnet" "hub_aadds_subnet" {
  name                 = "snet-aadds"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.5.0/24"]
}

# AADDS NSG — required ports for domain services and FSLogix profile containers
# TCP 636  : LDAPS (secure LDAP)
# TCP/UDP 389: LDAP
# TCP/UDP 88 : Kerberos authentication
# TCP/UDP 53 : DNS
# Microsoft automatically adds required inbound management rules (ports 443, 5986)
# when the AADDS instance is associated with this subnet.
resource "azurerm_network_security_group" "aadds_nsg" {
  name                = "nsg-aadds-${var.environment}"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  tags                = var.tags

  # LDAPS — secure LDAP for client workloads in spoke subnets
  security_rule {
    name                       = "Allow-LDAPS-TCP-636"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "636"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.5.0/24"
    description                = "Allow LDAPS from spoke subnets"
  }

  # LDAP (TCP)
  security_rule {
    name                       = "Allow-LDAP-TCP-389"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.5.0/24"
    description                = "Allow LDAP TCP from spoke subnets"
  }

  # LDAP (UDP)
  security_rule {
    name                       = "Allow-LDAP-UDP-389"
    priority                   = 111
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.5.0/24"
    description                = "Allow LDAP UDP from spoke subnets"
  }

  # Kerberos (TCP)
  security_rule {
    name                       = "Allow-Kerberos-TCP-88"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "88"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.5.0/24"
    description                = "Allow Kerberos TCP from spoke subnets"
  }

  # Kerberos (UDP)
  security_rule {
    name                       = "Allow-Kerberos-UDP-88"
    priority                   = 121
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "88"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.5.0/24"
    description                = "Allow Kerberos UDP from spoke subnets"
  }

  # DNS (TCP)
  security_rule {
    name                       = "Allow-DNS-TCP-53"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.5.0/24"
    description                = "Allow DNS TCP from spoke subnets"
  }

  # DNS (UDP)
  security_rule {
    name                       = "Allow-DNS-UDP-53"
    priority                   = 131
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.0.5.0/24"
    description                = "Allow DNS UDP from spoke subnets"
  }

  # Microsoft management traffic — AADDS requires inbound 443 and 5986 from AzureActiveDirectoryDomainServices tag
  security_rule {
    name                       = "Allow-AADDS-Management-443"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureActiveDirectoryDomainServices"
    destination_address_prefix = "10.0.5.0/24"
    description                = "Allow AADDS management HTTPS from Microsoft"
  }

  security_rule {
    name                       = "Allow-AADDS-Management-5986"
    priority                   = 141
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefix      = "AzureActiveDirectoryDomainServices"
    destination_address_prefix = "10.0.5.0/24"
    description                = "Allow AADDS management WinRM from Microsoft"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Deny all other inbound traffic"
  }
}

resource "azurerm_subnet_network_security_group_association" "hub_aadds_nsg" {
  subnet_id                 = azurerm_subnet.hub_aadds_subnet.id
  network_security_group_id = azurerm_network_security_group.aadds_nsg.id
}

resource "azurerm_public_ip" "firewall_pip" {
  name                = "pip-firewall-${var.environment}"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# NOTE: intrusion_detection requires sku = "Premium" on both the policy and
# the firewall. Standard-tier firewalls do not support the IDS/IDPS block.
resource "azurerm_firewall_policy" "hub_firewall_policy" {
  name                = "policy-firewall-${var.environment}"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  sku                 = "Premium"
  tags                = var.tags

  threat_intelligence_mode = "Deny"

  dns {
    proxy_enabled = true
    servers       = length(var.aadds_dns_server_ips) > 0 ? var.aadds_dns_server_ips : []
  }

  intrusion_detection {
    mode = "Deny"
  }
}

resource "azurerm_firewall" "hub_firewall" {
  name                = "fw-hub-${var.environment}"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id  = azurerm_firewall_policy.hub_firewall_policy.id
  threat_intel_mode   = "Deny"
  tags                = var.tags

  ip_configuration {
    name                 = "firewall-ip-config"
    subnet_id            = azurerm_subnet.hub_firewall_subnet.id
    public_ip_address_id = azurerm_public_ip.firewall_pip.id
  }
}

resource "azurerm_virtual_network" "shared_spoke_vnet" {
  name                = "vnet-shared-${var.environment}"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  address_space       = var.shared_spoke_vnet_address_space
  # Inject AADDS domain controller IPs as DNS servers so session hosts resolve the managed domain.
  # Set var.aadds_dns_server_ips after the first AADDS deployment then re-apply.
  dns_servers = length(var.aadds_dns_server_ips) > 0 ? var.aadds_dns_server_ips : []
  tags        = var.tags
}

resource "azurerm_subnet" "shared_app_subnet" {
  name                 = "snet-shared-app"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.shared_spoke_vnet.name
  address_prefixes     = ["10.1.0.0/24"]
}

resource "azurerm_subnet" "shared_avd_subnet" {
  name                 = "snet-shared-avd"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.shared_spoke_vnet.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet" "shared_storage_subnet" {
  name                 = "snet-shared-storage"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.shared_spoke_vnet.name
  address_prefixes     = ["10.1.2.0/24"]

  service_endpoints = ["Microsoft.Storage"]
}

resource "azurerm_virtual_network" "dedicated_spoke_vnet" {
  name                = "vnet-dedicated-${var.environment}"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  address_space       = var.dedicated_spoke_vnet_address_space
  # Inject AADDS domain controller IPs as DNS servers so session hosts resolve the managed domain.
  # Set var.aadds_dns_server_ips after the first AADDS deployment then re-apply.
  dns_servers = length(var.aadds_dns_server_ips) > 0 ? var.aadds_dns_server_ips : []
  tags        = var.tags
}

resource "azurerm_subnet" "dedicated_app_subnet" {
  name                 = "snet-dedicated-app"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.dedicated_spoke_vnet.name
  address_prefixes     = ["10.2.0.0/24"]
}

resource "azurerm_subnet" "dedicated_avd_subnet" {
  name                 = "snet-dedicated-avd"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.dedicated_spoke_vnet.name
  address_prefixes     = ["10.2.1.0/24"]
}

# Storage private endpoint subnet for the dedicated spoke.
# Private endpoints for per-customer FSLogix accounts and any dedicated App Attach
# accounts are placed here to keep storage traffic off the general AVD subnet.
resource "azurerm_subnet" "dedicated_storage_subnet" {
  name                 = "snet-dedicated-storage"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.dedicated_spoke_vnet.name
  address_prefixes     = ["10.2.2.0/24"]

  service_endpoints = ["Microsoft.Storage"]
}

resource "azurerm_network_security_group" "hub_nsg" {
  name                = "nsg-hub-${var.environment}"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-Management-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "10.0.2.0/24"
    description                = "Allow Azure Load Balancer health probes to management subnet"
  }

  security_rule {
    name                       = "Allow-AVD-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "10.0.3.0/24"
    description                = "Allow inbound HTTPS for AVD web access"
  }

  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow all traffic within the virtual network"
  }

  security_rule {
    name                       = "Allow-Internet-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.0.0.0/16"
    destination_address_prefix = "Internet"
    description                = "Allow internet outbound for all subnets"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Deny all other inbound traffic"
  }
}

resource "azurerm_network_security_group" "shared_spoke_nsg" {
  name                = "nsg-shared-${var.environment}"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-Hub-Management"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "10.0.2.0/24"
    destination_address_prefix = "10.1.0.0/24"
    description                = "Allow RDP from Hub management subnet"
  }

  security_rule {
    name                       = "Allow-Hub-AVD-Traffic"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "10.0.3.0/24"
    destination_address_prefix = "10.1.1.0/24"
    description                = "Allow HTTPS traffic from Hub frontend to AVD subnet"
  }

  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow traffic within shared spoke VNet"
  }

  security_rule {
    name                       = "Allow-Internet-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.1.0.0/16"
    destination_address_prefix = "Internet"
    description                = "Allow internet outbound"
  }

  security_rule {
    name                       = "Allow-Firewall-Outbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.1.0.0/16"
    destination_address_prefix = "10.0.1.0/24"
    description                = "Allow outbound to Azure Firewall"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Deny all other inbound traffic"
  }
}

resource "azurerm_network_security_group" "dedicated_spoke_nsg" {
  name                = "nsg-dedicated-${var.environment}"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-Hub-Management"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "10.0.2.0/24"
    destination_address_prefix = "10.2.0.0/24"
    description                = "Allow RDP from Hub management subnet"
  }

  security_rule {
    name                       = "Allow-Hub-AVD-Traffic"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "10.0.3.0/24"
    destination_address_prefix = "10.2.1.0/24"
    description                = "Allow HTTPS traffic from Hub frontend to AVD subnet"
  }

  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow traffic within dedicated spoke VNet"
  }

  security_rule {
    name                       = "Allow-Internet-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.2.0.0/16"
    destination_address_prefix = "Internet"
    description                = "Allow internet outbound"
  }

  security_rule {
    name                       = "Allow-Firewall-Outbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.2.0.0/16"
    destination_address_prefix = "10.0.1.0/24"
    description                = "Allow outbound to Azure Firewall"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Deny all other inbound traffic"
  }
}

resource "azurerm_subnet_network_security_group_association" "hub_management_nsg" {
  subnet_id                 = azurerm_subnet.hub_management_subnet.id
  network_security_group_id = azurerm_network_security_group.hub_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "hub_frontend_nsg" {
  subnet_id                 = azurerm_subnet.hub_frontend_subnet.id
  network_security_group_id = azurerm_network_security_group.hub_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "hub_backend_nsg" {
  subnet_id                 = azurerm_subnet.hub_backend_subnet.id
  network_security_group_id = azurerm_network_security_group.hub_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "shared_app_nsg" {
  subnet_id                 = azurerm_subnet.shared_app_subnet.id
  network_security_group_id = azurerm_network_security_group.shared_spoke_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "shared_avd_nsg" {
  subnet_id                 = azurerm_subnet.shared_avd_subnet.id
  network_security_group_id = azurerm_network_security_group.shared_spoke_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "shared_storage_nsg" {
  subnet_id                 = azurerm_subnet.shared_storage_subnet.id
  network_security_group_id = azurerm_network_security_group.shared_spoke_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "dedicated_app_nsg" {
  subnet_id                 = azurerm_subnet.dedicated_app_subnet.id
  network_security_group_id = azurerm_network_security_group.dedicated_spoke_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "dedicated_avd_nsg" {
  subnet_id                 = azurerm_subnet.dedicated_avd_subnet.id
  network_security_group_id = azurerm_network_security_group.dedicated_spoke_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "dedicated_storage_nsg" {
  subnet_id                 = azurerm_subnet.dedicated_storage_subnet.id
  network_security_group_id = azurerm_network_security_group.dedicated_spoke_nsg.id
}

resource "azurerm_virtual_network_peering" "hub_to_shared" {
  name                         = "peer-hub-to-shared"
  resource_group_name          = azurerm_resource_group.network_rg.name
  virtual_network_name         = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.shared_spoke_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "shared_to_hub" {
  name                         = "peer-shared-to-hub"
  resource_group_name          = azurerm_resource_group.network_rg.name
  virtual_network_name         = azurerm_virtual_network.shared_spoke_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.hub_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "hub_to_dedicated" {
  name                         = "peer-hub-to-dedicated"
  resource_group_name          = azurerm_resource_group.network_rg.name
  virtual_network_name         = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.dedicated_spoke_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "dedicated_to_hub" {
  name                         = "peer-dedicated-to-hub"
  resource_group_name          = azurerm_resource_group.network_rg.name
  virtual_network_name         = azurerm_virtual_network.dedicated_spoke_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.hub_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# ---------------------------------------------------------------------------
# Private DNS Zones
# ---------------------------------------------------------------------------
# Centralised Private DNS Zones for Azure PaaS services linked to the hub VNet.
# Downstream workload modules can reference the output IDs to create additional
# virtual network links from their own spokes without re-creating the zones.
locals {
  private_dns_zones = [
    "privatelink.file.core.windows.net",
    "privatelink.blob.core.windows.net",
  ]
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = toset(local.private_dns_zones)
  name                = each.value
  resource_group_name = azurerm_resource_group.network_rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each              = azurerm_private_dns_zone.this
  name                  = "link-${replace(each.key, ".", "-")}-hub"
  resource_group_name   = azurerm_resource_group.network_rg.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.hub_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}
