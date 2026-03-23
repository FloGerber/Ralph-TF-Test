mock_provider "azurerm" {
  mock_resource "azurerm_virtual_desktop_host_pool" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test/providers/Microsoft.DesktopVirtualization/hostPools/hp-avd-test"
    }
  }

  mock_resource "azurerm_virtual_desktop_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test/providers/Microsoft.DesktopVirtualization/workspaces/ws-avd-test"
    }
  }

  mock_resource "azurerm_virtual_desktop_application_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test/providers/Microsoft.DesktopVirtualization/applicationGroups/ag-avd-test"
    }
  }

  mock_resource "azurerm_virtual_desktop_workspace_application_group_association" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test/providers/Microsoft.DesktopVirtualization/workspaces/ws-avd-test/applicationGroupReferences/ag-avd-test"
    }
  }

  mock_resource "azurerm_virtual_desktop_host_pool_registration_info" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test/providers/Microsoft.DesktopVirtualization/hostPools/hp-avd-test/registrationInfo/default"
      # checkov:skip=CKV_SECRET_6: test fixture value, not a real secret
      token = "registration-token"
    }
  }

  mock_resource "azurerm_virtual_desktop_scaling_plan" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test/providers/Microsoft.DesktopVirtualization/scalingPlans/sp-avd-test"
    }
  }

  mock_resource "azurerm_orchestrated_virtual_machine_scale_set" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test/providers/Microsoft.Compute/virtualMachineScaleSets/vmss-avd-test"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-vmss-avd-test"
      principal_id = "00000000-0000-0000-0000-000000000123"
    }
  }
}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      # checkov:skip=CKV_SECRET_6: test fixture password, not a real secret
      id     = "session-host-password"
      result = "P@ssw0rd!P@ssw0rd!12"
    }
  }
}

variables {
  location            = "eastus"
  environment         = "test"
  resource_group_name = "rg-avd-test"

  tags = {
    environment = "test"
    workload    = "avd"
  }

  host_pool_config = [
    {
      name               = "hp-avd-test"
      friendly_name      = "AVD Test Host Pool"
      description        = "Synthetic host pool for module unit tests"
      type               = "Pooled"
      load_balancer_type = "BreadthFirst"
    }
  ]

  workspace_config            = []
  application_group_config    = []
  lob_application_config      = null
  app_attach_type             = "None"
  app_attach_packages         = []
  virtual_machine_config      = []
  network_interface_config    = []
  domain_join_config          = null
  fslogix_config              = null
  session_host_config         = []
  scaling_plan_config         = null
  dr_region                   = ""
  fslogix_storage_account_ids = []
  log_analytics_workspace_id  = ""
}

run "test_host_pool_created" {
  command = plan

  assert {
    condition     = length(keys(output.host_pool_ids)) > 0
    error_message = "Expected host_pool_ids to contain at least one host pool."
  }
}

run "test_app_group_workspace_association" {
  command = plan

  variables {
    workspace_config = [
      {
        name        = "ws-avd-test"
        description = "Synthetic workspace for unit tests"
      }
    ]

    application_group_config = [
      {
        name           = "ag-avd-test"
        host_pool_name = "hp-avd-test"
        workspace_name = "ws-avd-test"
        type           = "Desktop"
        description    = "Synthetic application group for unit tests"
      }
    ]
  }

  assert {
    condition     = length(azurerm_virtual_desktop_workspace_application_group_association.this) == 1
    error_message = "Expected one workspace/application group association in the plan."
  }
}

run "test_vmss_session_hosts" {
  command = plan

  variables {
    session_host_config = [
      {
        vmss_name      = "vmss-avd-test"
        host_pool_name = "hp-avd-test"
        admin_username = "avdadmin"
        subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avd-test/providers/Microsoft.Network/virtualNetworks/vnet-avd-test/subnets/session-hosts"
      }
    ]
  }

  assert {
    condition     = length(azurerm_orchestrated_virtual_machine_scale_set.session_hosts) == 1
    error_message = "Expected one session host VMSS in the plan."
  }
}

run "test_scaling_plan_optional" {
  command = plan

  variables {
    scaling_plan_config = null
  }

  assert {
    condition     = length(azurerm_virtual_desktop_scaling_plan.this) == 0
    error_message = "Expected no scaling plan resource when scaling_plan_config is null."
  }
}

run "test_scaling_plan_optional_enabled" {
  command = plan

  variables {
    scaling_plan_config = {
      name          = "sp-avd-test"
      friendly_name = "Synthetic scaling plan"
      description   = "Synthetic scaling plan for unit tests"
      time_zone     = "UTC"
      schedules = [
        {
          name                 = "weekday"
          days_of_week         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
          ramp_up_start_time   = "06:00"
          peak_start_time      = "08:00"
          ramp_down_start_time = "18:00"
          off_peak_start_time  = "20:00"
        }
      ]
      host_pools = [
        {
          hostpool_name        = "hp-avd-test"
          scaling_plan_enabled = true
        }
      ]
    }
  }

  assert {
    condition     = length(azurerm_virtual_desktop_scaling_plan.this) == 1
    error_message = "Expected one scaling plan resource when scaling_plan_config is provided."
  }
}
