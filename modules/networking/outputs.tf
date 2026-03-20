# modules/networking/outputs.tf — Outputs from the networking module.

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.this.id
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.this.name
}

output "vnet_address_space" {
  description = "Address space of the virtual network"
  value       = azurerm_virtual_network.this.address_space
}

output "subnet_ids" {
  description = "IDs of the subnets"
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.id }
}

output "subnet_names" {
  description = "Names of the subnets"
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.name }
}

output "nsg_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.this.id
}

output "firewall_id" {
  description = "ID of the Azure Firewall (if enabled)"
  value       = try(azurerm_firewall.this[0].id, null)
}

output "firewall_private_ip" {
  description = "Private IP of the Azure Firewall (if enabled)"
  value       = try(azurerm_firewall.this[0].ip_configuration[0].private_ip_address, null)
}

output "firewall_public_ip" {
  description = "Public IP of the Azure Firewall (if enabled)"
  value       = try(azurerm_public_ip.firewall[0].ip_address, null)
}

output "peering_ids" {
  description = "IDs of virtual network peering resources"
  value = concat(
    [for peering in azurerm_virtual_network_peering.this : peering.id],
    [for peering in azurerm_virtual_network_peering.reverse : peering.id]
  )
}
