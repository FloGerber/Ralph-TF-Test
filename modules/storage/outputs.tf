# modules/storage/outputs.tf — Outputs from the storage module.

output "storage_account_ids" {
  description = "IDs of the storage accounts"
  value       = { for name, account in azurerm_storage_account.this : name => account.id }
}

output "storage_account_names" {
  description = "Names of the storage accounts"
  value       = { for name, account in azurerm_storage_account.this : name => account.name }
}

output "storage_account_primary_endpoints" {
  description = "Primary endpoints of the storage accounts"
  value       = { for name, account in azurerm_storage_account.this : name => account.primary_blob_endpoint }
}

output "storage_account_file_endpoints" {
  description = "File endpoints of the storage accounts"
  value       = { for name, account in azurerm_storage_account.this : name => account.primary_file_endpoint }
}

output "file_share_ids" {
  description = "IDs of the file shares"
  value       = { for name, share in azurerm_storage_share.this : name => share.id }
}

output "file_share_names" {
  description = "Names of the file shares keyed by composite key (storage_account_name-share_name)"
  value       = { for name, share in azurerm_storage_share.this : name => share.name }
}

output "file_share_urls" {
  description = "URLs of the file shares"
  value       = { for name, share in azurerm_storage_share.this : name => share.url }
}

output "private_endpoint_ids" {
  description = "IDs of the private endpoints"
  value       = { for name, endpoint in azurerm_private_endpoint.this : name => endpoint.id }
}

output "private_endpoint_fqdns" {
  description = "FQDNs of the private endpoints (from the private DNS zone group A-record)"
  value = {
    for name, endpoint in azurerm_private_endpoint.this :
    name => try(endpoint.private_dns_zone_configs[0].record_sets[0].fqdn, null)
  }
}

output "private_endpoint_ip_addresses" {
  description = "Private IP addresses of the private endpoints"
  value = {
    for name, endpoint in azurerm_private_endpoint.this :
    name => try(endpoint.private_service_connection[0].private_ip_address, null)
  }
}
