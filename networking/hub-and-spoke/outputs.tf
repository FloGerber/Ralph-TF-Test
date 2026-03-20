# -----------------------------------------------------------------------------
# networking/hub-and-spoke/outputs.tf
#
# Outputs exported by the hub-and-spoke root module.
# Downstream root modules (environments/shared, environments/dedicated) consume
# hub_vnet_id, hub_firewall_private_ip, subnet_ids, and hub_aadds_subnet_id.
# Private DNS zone IDs are consumed by the shared environment for Private Endpoints.
# -----------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the network resource group"
  value       = azurerm_resource_group.network_rg.name
}

output "resource_group_id" {
  description = "ID of the network resource group"
  value       = azurerm_resource_group.network_rg.id
}

output "hub_vnet_id" {
  description = "ID of the Hub VNet"
  value       = azurerm_virtual_network.hub_vnet.id
}

output "hub_vnet_name" {
  description = "Name of the Hub VNet"
  value       = azurerm_virtual_network.hub_vnet.name
}

output "hub_firewall_policy_id" {
  description = "ID of the Azure Firewall Policy"
  value       = azurerm_firewall_policy.hub_firewall_policy.id
}

output "hub_firewall_id" {
  description = "ID of the Azure Firewall"
  value       = azurerm_firewall.hub_firewall.id
}

output "hub_firewall_private_ip" {
  description = "Private IP of the Azure Firewall"
  value       = azurerm_firewall.hub_firewall.ip_configuration[0].private_ip_address
}

output "firewall_dns_proxy_enabled" {
  description = "Whether Azure Firewall DNS proxy is enabled"
  value       = true
}

output "shared_spoke_vnet_id" {
  description = "ID of the Shared Hosting spoke VNet"
  value       = azurerm_virtual_network.shared_spoke_vnet.id
}

output "shared_spoke_vnet_name" {
  description = "Name of the Shared Hosting spoke VNet"
  value       = azurerm_virtual_network.shared_spoke_vnet.name
}

output "shared_app_subnet_id" {
  description = "ID of the Shared Hosting app subnet"
  value       = azurerm_subnet.shared_app_subnet.id
}

output "shared_app_subnet_name" {
  description = "Name of the Shared Hosting app subnet"
  value       = azurerm_subnet.shared_app_subnet.name
}

output "shared_avd_subnet_id" {
  description = "ID of the Shared Hosting AVD subnet"
  value       = azurerm_subnet.shared_avd_subnet.id
}

output "shared_avd_subnet_name" {
  description = "Name of the Shared Hosting AVD subnet"
  value       = azurerm_subnet.shared_avd_subnet.name
}

output "shared_storage_subnet_id" {
  description = "ID of the Shared Hosting FSLogix storage subnet"
  value       = azurerm_subnet.shared_storage_subnet.id
}

output "shared_storage_subnet_name" {
  description = "Name of the Shared Hosting FSLogix storage subnet"
  value       = azurerm_subnet.shared_storage_subnet.name
}

output "dedicated_spoke_vnet_id" {
  description = "ID of the Dedicated Hosting spoke VNet"
  value       = azurerm_virtual_network.dedicated_spoke_vnet.id
}

output "dedicated_spoke_vnet_name" {
  description = "Name of the Dedicated Hosting spoke VNet"
  value       = azurerm_virtual_network.dedicated_spoke_vnet.name
}

output "hub_nsg_id" {
  description = "ID of the Hub NSG"
  value       = azurerm_network_security_group.hub_nsg.id
}

output "shared_spoke_nsg_id" {
  description = "ID of the Shared Hosting spoke NSG"
  value       = azurerm_network_security_group.shared_spoke_nsg.id
}

output "dedicated_spoke_nsg_id" {
  description = "ID of the Dedicated Hosting spoke NSG"
  value       = azurerm_network_security_group.dedicated_spoke_nsg.id
}

output "subnet_ids" {
  description = "Map of subnet logical names to subnet IDs"
  value = {
    hub_gateway       = azurerm_subnet.hub_gateway_subnet.id
    hub_firewall      = azurerm_subnet.hub_firewall_subnet.id
    hub_management    = azurerm_subnet.hub_management_subnet.id
    hub_frontend      = azurerm_subnet.hub_frontend_subnet.id
    hub_backend       = azurerm_subnet.hub_backend_subnet.id
    hub_aadds         = azurerm_subnet.hub_aadds_subnet.id
    shared_app        = azurerm_subnet.shared_app_subnet.id
    shared_avd        = azurerm_subnet.shared_avd_subnet.id
    shared_storage    = azurerm_subnet.shared_storage_subnet.id
    dedicated_app     = azurerm_subnet.dedicated_app_subnet.id
    dedicated_avd     = azurerm_subnet.dedicated_avd_subnet.id
    dedicated_storage = azurerm_subnet.dedicated_storage_subnet.id
  }
}

output "hub_aadds_subnet_id" {
  description = "ID of the AADDS subnet (snet-aadds, 10.0.5.0/24) — pass to the aadds module as aadds_subnet_id"
  value       = azurerm_subnet.hub_aadds_subnet.id
}

output "aadds_nsg_id" {
  description = "ID of the AADDS NSG"
  value       = azurerm_network_security_group.aadds_nsg.id
}

output "private_dns_zone_ids" {
  description = "Map of Private DNS Zone names to resource IDs"
  value       = { for k, v in azurerm_private_dns_zone.this : k => v.id }
}
