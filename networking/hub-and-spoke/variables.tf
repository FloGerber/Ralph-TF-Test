# -----------------------------------------------------------------------------
# networking/hub-and-spoke/variables.tf
#
# Input variables for the hub-and-spoke root module.
# Defines address spaces for hub and spoke VNets, AADDS DNS server IPs (required
# for the two-pass deployment pattern), location, and tagging.
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
  default     = "rg-avd-networking"
}

variable "hub_vnet_address_space" {
  description = "Address space for Hub VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "shared_spoke_vnet_address_space" {
  description = "Address space for Shared Hosting spoke VNet"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "dedicated_spoke_vnet_address_space" {
  description = "Address space for Dedicated Hosting spoke VNet"
  type        = list(string)
  default     = ["10.2.0.0/16"]
}

variable "aadds_dns_server_ips" {
  description = "AADDS domain controller IP addresses to inject as DNS servers into spoke VNets; populate after AADDS deployment (two-pass). Obtain from the aadds module output 'domain_controller_ips' after the first deployment and re-apply to ensure domain name resolution on session hosts."
  type        = list(string)
  default     = []
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
