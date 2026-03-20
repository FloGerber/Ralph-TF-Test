mock_provider "azurerm" {
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test"
    }
  }

  mock_resource "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.Network/virtualNetworks/vnet-dedicated-test"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.Network/virtualNetworks/vnet-dedicated-test/subnets/subnet-test"
    }
  }

  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.Network/networkSecurityGroups/nsg-dedicated-test"
    }
  }

  mock_resource "azurerm_subnet_network_security_group_association" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.Network/virtualNetworks/vnet-dedicated-test/subnets/subnet-test/providers/Microsoft.Network/networkSecurityGroupAssociations/default"
    }
  }

  mock_resource "azurerm_virtual_network_peering" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.Network/virtualNetworks/vnet-dedicated-test/virtualNetworkPeerings/peer-dedicated-test"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.Storage/storageAccounts/stdedicatedtest"
      primary_blob_endpoint = "https://stdedicatedtest.blob.core.windows.net/"
      primary_file_endpoint = "https://stdedicatedtest.file.core.windows.net/"
    }
  }

  mock_resource "azurerm_storage_share" {
    defaults = {
      id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.Storage/storageAccounts/stdedicatedtest/fileServices/default/shares/profiles"
      url = "https://stdedicatedtest.file.core.windows.net/profiles"
    }
  }

  mock_resource "azurerm_storage_account_network_rules" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.Storage/storageAccounts/stdedicatedtest/networkAcls/default"
    }
  }

  mock_resource "azurerm_private_endpoint" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.Network/privateEndpoints/pe-dedicated-test"
    }
  }

  mock_resource "azurerm_virtual_desktop_host_pool" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.DesktopVirtualization/hostPools/hp-dedicated-test"
    }
  }

  mock_resource "azurerm_virtual_desktop_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.DesktopVirtualization/workspaces/ws-dedicated-test"
    }
  }

  mock_resource "azurerm_virtual_desktop_application_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.DesktopVirtualization/applicationGroups/ag-dedicated-test"
    }
  }

  mock_resource "azurerm_virtual_desktop_workspace_application_group_association" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.DesktopVirtualization/workspaces/ws-dedicated-test/applicationGroupReferences/ag-dedicated-test"
    }
  }

  mock_resource "azurerm_virtual_desktop_host_pool_registration_info" {
    defaults = {
      id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.DesktopVirtualization/hostPools/hp-dedicated-test/registrationInfo/default"
      token = "registration-token"
    }
  }

  mock_resource "azurerm_orchestrated_virtual_machine_scale_set" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.Compute/virtualMachineScaleSets/vmss-dedicated-test"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dedicated-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-vmss-dedicated-test"
      principal_id = "00000000-0000-0000-0000-000000000123"
    }
  }
}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      id     = "session-host-password"
      result = "P@ssw0rd!P@ssw0rd!12"
    }
  }
}

variables {
  user_count   = 25
  avd_image_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-images-test/providers/Microsoft.Compute/images/img-avd-golden"

  tags = {
    environment = "test"
    workload    = "dedicated"
  }

  nsg_rules                  = []
  storage_account_config     = []
  file_shares                = []
  enable_private_endpoints   = true
  private_dns_zone_file_id   = null
  host_pool_config           = []
  workspace_config           = []
  application_group_config   = []
  session_host_config        = []
  hub_vnet_id                = ""
  hub_vnet_name              = ""
  aadds_dns_servers          = []
  hub_firewall_private_ip    = ""
  domain_join_config         = null
  fslogix_config             = null
  app_attach_type            = "None"
  app_attach_packages        = []
  appattach_quota_gib        = 0
  log_analytics_workspace_id = ""
  fslogix_rbac_principal_id  = ""
}

run "test_default_dedicated_module" {
  command = plan

  variables {
    customer_name       = "contoso"
    location            = "eastus"
    resource_group_name = "rg-dedicated-test"
    vnet_config = {
      address_spaces = ["10.50.0.0/16"]
      subnets = [
        {
          name              = "dedicated-avd"
          address_prefixes  = ["10.50.1.0/24"]
          service_endpoints = []
          delegations       = []
        },
        {
          name              = "snet-dedicated-storage"
          address_prefixes  = ["10.50.2.0/24"]
          service_endpoints = []
          delegations       = []
        }
      ]
    }
  }

  assert {
    condition     = length(keys(output.host_pool_ids)) > 0
    error_message = "Expected host_pool_ids to contain at least one host pool."
  }
}

run "test_hub_peering" {
  command = plan

  variables {
    customer_name       = "fabrikam"
    location            = "eastus"
    resource_group_name = "rg-dedicated-test"
    vnet_config = {
      address_spaces = ["10.60.0.0/16"]
      subnets = [
        {
          name              = "dedicated-avd"
          address_prefixes  = ["10.60.1.0/24"]
          service_endpoints = []
          delegations       = []
        },
        {
          name              = "snet-dedicated-storage"
          address_prefixes  = ["10.60.2.0/24"]
          service_endpoints = []
          delegations       = []
        }
      ]
    }
    hub_vnet_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-test/providers/Microsoft.Network/virtualNetworks/vnet-hub-test"
    hub_vnet_name = "vnet-hub-test"
  }

  assert {
    condition     = length(output.peering_ids) >= 1
    error_message = "Expected at least one virtual network peering resource when hub peering is configured."
  }
}
