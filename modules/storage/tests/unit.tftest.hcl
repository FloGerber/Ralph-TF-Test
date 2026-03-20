mock_provider "azurerm" {
  mock_resource "azurerm_storage_account" {
    defaults = {
      id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-storage-test/providers/Microsoft.Storage/storageAccounts/ststorageaccttest"
      primary_blob_endpoint = "https://ststorageaccttest.blob.core.windows.net/"
      primary_file_endpoint = "https://ststorageaccttest.file.core.windows.net/"
    }
  }

  mock_resource "azurerm_storage_share" {
    defaults = {
      id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-storage-test/providers/Microsoft.Storage/storageAccounts/ststorageaccttest/fileServices/default/shares/sharetest"
      url = "https://ststorageaccttest.file.core.windows.net/sharetest"
    }
  }

  mock_resource "azurerm_storage_account_network_rules" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-storage-test/providers/Microsoft.Storage/storageAccounts/ststorageaccttest/networkAcls/default"
    }
  }

  mock_resource "azurerm_private_endpoint" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-storage-test/providers/Microsoft.Network/privateEndpoints/pe-storage-test"
    }
  }
}

variables {
  location            = "eastus"
  environment         = "test"
  resource_group_name = "rg-storage-test"

  tags = {
    environment = "test"
    workload    = "storage"
  }

  storage_account_config       = []
  file_shares                  = []
  private_endpoint_config      = []
  rbac_assignments             = []
  vnet_ids                     = []
  enable_geo_redundant_storage = false
}

run "test_storage_accounts_created" {
  command = plan

  variables {
    storage_account_config = [
      {
        name             = "ststoragetesta"
        account_kind     = "StorageV2"
        account_tier     = "Standard"
        replication_type = "ZRS"
        is_hns_enabled   = false
        blob_services = {
          delete_retention_days = 7
        }
      },
      {
        name             = "ststoragetestb"
        account_kind     = "StorageV2"
        account_tier     = "Standard"
        replication_type = "ZRS"
        is_hns_enabled   = false
        blob_services = {
          delete_retention_days = 14
        }
      }
    ]
  }

  assert {
    condition     = length(azurerm_storage_account.this) == 2
    error_message = "Expected two storage account resources in the plan."
  }
}

run "test_file_shares_created" {
  command = plan

  variables {
    storage_account_config = [
      {
        name             = "stfilesharetest"
        account_kind     = "FileStorage"
        account_tier     = "Premium"
        replication_type = "ZRS"
        is_hns_enabled   = false
        blob_services    = null
      }
    ]

    file_shares = [
      {
        name                 = "profiles"
        storage_account_name = "stfilesharetest"
        quota_gib            = 100
        access_tier          = "Premium"
      },
      {
        name                 = "appattach"
        storage_account_name = "stfilesharetest"
        quota_gib            = 200
        access_tier          = "Premium"
      }
    ]
  }

  assert {
    condition     = length(azurerm_storage_share.this) == 2
    error_message = "Expected two storage share resources in the plan."
  }
}

run "test_private_endpoints_optional" {
  command = plan

  variables {
    storage_account_config = [
      {
        name             = "stprivateoff"
        account_kind     = "FileStorage"
        account_tier     = "Premium"
        replication_type = "ZRS"
        is_hns_enabled   = false
        blob_services    = null
      }
    ]

    private_endpoint_config = []
  }

  assert {
    condition     = length(azurerm_private_endpoint.this) == 0
    error_message = "Expected no private endpoint resources when private_endpoint_config is empty."
  }
}

run "test_private_endpoints_optional_enabled" {
  command = plan

  variables {
    storage_account_config = [
      {
        name             = "stprivateon"
        account_kind     = "FileStorage"
        account_tier     = "Premium"
        replication_type = "ZRS"
        is_hns_enabled   = false
        blob_services    = null
      }
    ]

    private_endpoint_config = [
      {
        name                 = "stprivateon"
        storage_account_name = "stprivateon"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-storage-test/providers/Microsoft.Network/virtualNetworks/vnet-storage-test/subnets/snet-storage"
        private_dns_zone_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns-test/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      }
    ]
  }

  assert {
    condition     = length(azurerm_private_endpoint.this) == 1
    error_message = "Expected one private endpoint resource when private_endpoint_config includes one entry."
  }
}
