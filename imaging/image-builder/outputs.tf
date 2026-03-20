# -----------------------------------------------------------------------------
# imaging/image-builder/outputs.tf
#
# Outputs exported by the image-builder root module.
# Key outputs consumed by environment root modules:
#   - gallery_image_id   → passed as avd_image_id to dedicated/shared modules
#   - image_template_name → used to trigger AIB builds via az image builder run
# -----------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the image builder resource group"
  value       = azurerm_resource_group.image_builder_rg.name
}

output "resource_group_id" {
  description = "ID of the image builder resource group"
  value       = azurerm_resource_group.image_builder_rg.id
}

output "image_builder_template_name" {
  description = "Name of the image builder template"
  value       = azapi_resource.image_template.name
}

output "image_builder_template_id" {
  description = "ID of the image builder template"
  value       = azapi_resource.image_template.id
}

output "managed_identity_name" {
  description = "Name of the managed identity"
  value       = azurerm_user_assigned_identity.image_builder_identity.name
}

output "managed_identity_principal_id" {
  description = "Principal ID of the managed identity"
  value       = azurerm_user_assigned_identity.image_builder_identity.principal_id
}

output "managed_identity_resource_id" {
  description = "Resource ID of the managed identity"
  value       = azurerm_user_assigned_identity.image_builder_identity.id
}

output "shared_image_gallery_name" {
  description = "Name of the Shared Image Gallery"
  value       = var.create_shared_gallery ? azurerm_shared_image_gallery.gallery[0].name : null
}

output "shared_image_gallery_id" {
  description = "ID of the Shared Image Gallery"
  value       = var.create_shared_gallery ? azurerm_shared_image_gallery.gallery[0].id : null
}

output "shared_image_name" {
  description = "Name of the shared image"
  value       = var.create_shared_gallery ? azurerm_shared_image.windows_11_image[0].name : null
}

output "shared_image_id" {
  description = "ID of the shared image"
  value       = var.create_shared_gallery ? azurerm_shared_image.windows_11_image[0].id : null
}

output "staging_storage_account_name" {
  description = "Name of the staging storage account"
  value       = var.create_staging_storage ? azurerm_storage_account.staging[0].name : null
}

output "staging_storage_endpoint" {
  description = "Blob endpoint of the staging storage account"
  value       = var.create_staging_storage ? azurerm_storage_account.staging[0].primary_blob_endpoint : null
}

# Convenience aliases required by US-007 acceptance criteria
output "gallery_image_id" {
  description = "Resource ID of the Shared Image Gallery image definition (used by Flexible VMSS as source image)"
  value       = var.create_shared_gallery ? azurerm_shared_image.windows_11_image[0].id : null
}

output "image_template_name" {
  description = "Name of the Azure Image Builder image template"
  value       = azapi_resource.image_template.name
}
