# environments/dedicated/outputs.tf — Outputs from the dedicated AVD environment.

output "resource_group_name" {
  description = "Name of the dedicated resource group"
  value       = local.resource_group_name
}

output "location" {
  description = "Azure region"
  value       = local.location
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = module.networking.vnet_name
}

output "subnet_ids" {
  description = "IDs of the subnets"
  value       = module.networking.subnet_ids
}

output "firewall_id" {
  description = "ID of the Azure Firewall"
  value       = module.networking.firewall_id
}

output "firewall_private_ip" {
  description = "Private IP of the Azure Firewall"
  value       = module.networking.firewall_private_ip
}

output "storage_account_names" {
  description = "Names of the storage accounts"
  value       = module.storage.storage_account_names
}

output "file_share_urls" {
  description = "URLs of the file shares"
  value       = module.storage.file_share_urls
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = module.monitoring.log_analytics_workspace_name
}

output "host_pool_id" {
  description = "ID of the AVD host pool"
  value       = try(module.avd.host_pool_ids["hp-dedicated-pool"], null)
}

output "host_pool_fqdn" {
  description = "FQDN of the AVD host pool"
  value       = try(module.avd.host_pool_fqdns["hp-dedicated-pool"], null)
}

output "workspace_url" {
  description = "URL of the AVD workspace"
  value       = try(module.avd.workspace_urls["ws-dedicated-workspace"], null)
}
