# -----------------------------------------------------------------------------
# imaging/image-builder/variables.tf
#
# Input variables for the image-builder root module.
# Controls the AIB template, Shared Image Gallery, source platform image
# (publisher/offer/SKU/version), customization scripts, replication regions,
# and build-automation triggers.
# -----------------------------------------------------------------------------

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
  default     = "prod"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-avd-image-builder"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Production"
    Project     = "AVD"
    ManagedBy   = "OpenTofu"
  }
}

variable "source_image_publisher" {
  description = "Marketplace publisher for the base (source) platform image used by Image Builder"
  type        = string
  default     = "MicrosoftWindowsDesktop"
}

variable "source_image_offer" {
  description = "Marketplace offer for the base (source) platform image used by Image Builder"
  type        = string
  default     = "windows-11"
}

variable "source_image_sku" {
  description = "Marketplace SKU for the base (source) platform image used by Image Builder"
  type        = string
  default     = "win11-23h2-avd"
}

variable "source_image_version" {
  description = "Marketplace version for the base (source) platform image used by Image Builder (use 'latest' for the most recent)"
  type        = string
  default     = "latest"
}

variable "image_publisher" {
  description = "Publisher identifier recorded in the Shared Image Gallery image definition"
  type        = string
  default     = "MicrosoftWindowsDesktop"
}

variable "image_offer" {
  description = "Offer identifier recorded in the Shared Image Gallery image definition"
  type        = string
  default     = "windows-11"
}

variable "image_sku" {
  description = "SKU identifier recorded in the Shared Image Gallery image definition"
  type        = string
  default     = "win11-23h2-avd"
}

variable "create_shared_gallery" {
  description = "Whether to create a Shared Image Gallery"
  type        = bool
  default     = true
}

variable "replication_regions" {
  description = "Regions to replicate the image to"
  type        = list(string)
  default     = ["eastus", "westeurope"]
}

variable "create_staging_storage" {
  description = "Whether to create staging storage account"
  type        = bool
  default     = false
}

variable "staging_storage_account_blob_endpoint" {
  description = "Blob endpoint for staging storage account"
  type        = string
  default     = "https://stgavdib.blob.core.windows.net/"
}
