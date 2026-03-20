# modules/networking/variables.tf — Input variables for the networking module.

variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vnet_config" {
  description = "Configuration for virtual networks"
  type = object({
    address_spaces = list(string)
    subnets = list(object({
      name              = string
      address_prefixes  = list(string)
      service_endpoints = optional(list(string), [])
      delegations       = optional(list(string), [])
    }))
  })
  default = {
    address_spaces = ["10.0.0.0/16"]
    subnets        = []
  }
}

variable "enable_firewall" {
  description = "Whether to deploy Azure Firewall"
  type        = bool
  default     = false
}

variable "enable_peering" {
  description = "Whether to enable VNet peering"
  type        = bool
  default     = false
}

variable "peering_config" {
  description = "Configuration for VNet peering"
  type = object({
    remote_vnet_id          = string
    remote_vnet_name        = string
    allow_forwarded_traffic = optional(bool, false)
    allow_gateway_transit   = optional(bool, false)
  })
  default = null
}

variable "dns_servers" {
  description = "Optional list of DNS server IPs to assign to the VNet (e.g. AADDS domain controller IPs). Defaults to Azure-provided DNS when empty."
  type        = list(string)
  default     = []
}

variable "nsg_rules" {
  description = "Network security group rules"
  type = list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = optional(string, "*")
    destination_port_range     = optional(string, "*")
    source_address_prefix      = optional(string, "*")
    destination_address_prefix = optional(string, "*")
  }))
  default = []
}
