# modules/dedicated/outputs.tf — Outputs from the dedicated AVD composite module.

output "resource_group_name" {
  description = "Name of the customer-specific resource group"
  value       = module.networking.resource_group_name
}

output "resource_group_id" {
  description = "ID of the customer-specific resource group"
  value       = module.networking.resource_group_id
}

output "vnet_id" {
  description = "ID of the customer-dedicated spoke VNet"
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "Name of the customer-dedicated spoke VNet"
  value       = module.networking.vnet_name
}

output "vnet_address_space" {
  description = "Address space of the customer-dedicated spoke VNet"
  value       = module.networking.vnet_address_space
}

output "subnet_ids" {
  description = "IDs of all subnets in the customer-dedicated spoke VNet"
  value       = module.networking.subnet_ids
}

output "subnet_names" {
  description = "Names of all subnets in the customer-dedicated spoke VNet"
  value       = module.networking.subnet_names
}

output "nsg_id" {
  description = "ID of the network security group for the customer spoke"
  value       = module.networking.nsg_id
}

output "peering_ids" {
  description = "IDs of virtual network peering resources for the customer spoke"
  value       = module.networking.peering_ids
}

output "workspace_ids" {
  description = "IDs of the AVD workspaces created for this customer"
  value       = module.avd.workspace_ids
}

output "workspace_urls" {
  description = "URLs of the AVD workspaces created for this customer"
  value       = module.avd.workspace_urls
}

output "host_pool_ids" {
  description = "IDs of the AVD host pools created for this customer"
  value       = module.avd.host_pool_ids
}

output "host_pool_names" {
  description = "Names of the AVD host pools created for this customer"
  value       = module.avd.host_pool_names
}

output "host_pool_registration_token" {
  description = "Registration token for the AVD host pool (sensitive)"
  value       = module.avd.registration_token
  sensitive   = true
}

output "application_group_ids" {
  description = "IDs of the AVD application groups"
  value       = module.avd.application_group_ids
}

output "storage_account_ids" {
  description = "IDs of the storage accounts created for FSLogix"
  value       = module.storage.storage_account_ids
}

output "storage_account_names" {
  description = "Names of the storage accounts created for FSLogix"
  value       = module.storage.storage_account_names
}

output "storage_account_file_endpoints" {
  description = "File endpoints of the storage accounts (used for FSLogix mount paths)"
  value       = module.storage.storage_account_file_endpoints
}

output "file_share_ids" {
  description = "IDs of the file shares created for FSLogix profiles"
  value       = module.storage.file_share_ids
}

output "file_share_names" {
  description = "Names of the file shares (profiles + optional appattach)"
  value       = module.storage.file_share_names
}

output "file_share_urls" {
  description = "URLs of the file shares (use for FSLogix profile container paths)"
  value       = module.storage.file_share_urls
}

output "private_endpoint_ids" {
  description = "IDs of the private endpoints for storage accounts (if enabled)"
  value       = module.storage.private_endpoint_ids
}

output "private_endpoint_fqdns" {
  description = "FQDNs of the private endpoints (requires hub DNS zone to be set)"
  value       = module.storage.private_endpoint_fqdns
}

output "virtual_machine_ids" {
  description = "IDs of the AVD session host virtual machines"
  value       = module.avd.virtual_machine_ids
}

output "customer_name" {
  description = "Customer identifier used for naming resources"
  value       = var.customer_name
}

output "user_count" {
  description = "Number of concurrent users configured for auto-scaling"
  value       = var.user_count
}

output "min_session_hosts" {
  description = "Minimum number of session hosts for auto-scaling"
  value       = local.min_instances
}

output "max_session_hosts" {
  description = "Maximum number of session hosts for auto-scaling"
  value       = local.max_instances
}
