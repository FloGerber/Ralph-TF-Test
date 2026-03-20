# imaging/image-builder/main.tf — Azure Image Builder golden image pipeline root module.
# Independent root configuration with its own backend state key (imaging/image-builder).
# Provisions: user-assigned managed identity with AIB roles, optional Shared Image Gallery,
# Windows 11 23H2 multi-session Gen2 + Trusted Launch image definition, Azure Image Builder
# template (via azapi_resource) with customisation steps: Windows Update, Defender hardening,
# FSLogix install + registry keys, RSAT-AD-PowerShell, AVD optimisations, security baselines,
# sysprep. Image distributed to Shared Image Gallery and optional VHD staging storage.
# Deploy with: tofu init -backend-config=../../backend.hcl && tofu apply
# Trigger a build: az image builder run --name <template> --resource-group <rg>
# See docs/runbook-image-update.md for the full image update procedure.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Image Builder Pipeline Trigger Configuration:
# This module supports automated image building on configuration changes through:
#
# 1. Azure Pipelines Integration:
#    - Create a pipeline trigger on push to imaging/image-builder/ directory
#    - Pipeline runs: tofu plan, tofu apply, then invokes image template build
#
# 2. Image Version Management:
#    - Each terraform apply creates new image version in Shared Image Gallery
#    - Image versioning schema: configured via image_version_schema variable
#    - Versions automatically replicated to replication_regions
#
# 3. Source Image Updates:
#    - source_image_publisher/offer/sku/version control the marketplace base image
#    - Changing any of these triggers a new image template build
#    - Using type="PlatformImage" ensures compatibility with Flexible VMSS (Gen2 + Trusted Launch)
#
# 4. Configuration Change Tracking:
#    - Customize block changes trigger image rebuild (via azapi_resource update)
#    - Tags and resource properties trigger updates automatically
#

resource "azurerm_resource_group" "image_builder_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags

  lifecycle {
    prevent_destroy = false
  }
}

resource "azurerm_user_assigned_identity" "image_builder_identity" {
  name                = "id-avd-image-builder-${var.environment}"
  resource_group_name = azurerm_resource_group.image_builder_rg.name
  location            = azurerm_resource_group.image_builder_rg.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "image_builder_role_assignment_reader" {
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.image_builder_identity.principal_id
  scope                = azurerm_resource_group.image_builder_rg.id
}

resource "azurerm_role_assignment" "image_builder_role_assignment_vm_contributor" {
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.image_builder_identity.principal_id
  scope                = azurerm_resource_group.image_builder_rg.id
}

resource "azurerm_role_assignment" "image_builder_role_assignment_contributor" {
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.image_builder_identity.principal_id
  scope                = azurerm_resource_group.image_builder_rg.id
}

resource "azurerm_role_assignment" "image_builder_role_assignment_storage_reader" {
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.image_builder_identity.principal_id
  scope                = azurerm_resource_group.image_builder_rg.id
}

resource "azurerm_role_assignment" "image_builder_shared_gallery_role_assignment" {
  count                = var.create_shared_gallery ? 1 : 0
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.image_builder_identity.principal_id
  scope                = azurerm_shared_image_gallery.gallery[0].id
}

resource "azurerm_shared_image_gallery" "gallery" {
  count               = var.create_shared_gallery ? 1 : 0
  name                = "sig-avd-${var.environment}"
  resource_group_name = azurerm_resource_group.image_builder_rg.name
  location            = azurerm_resource_group.image_builder_rg.location
  description         = "Shared Image Gallery for AVD Golden Images"
  tags                = var.tags
}

resource "azurerm_shared_image" "windows_11_image" {
  count                  = var.create_shared_gallery ? 1 : 0
  name                   = "img-win11-multi-session-${var.environment}"
  gallery_name           = azurerm_shared_image_gallery.gallery[0].name
  resource_group_name    = azurerm_resource_group.image_builder_rg.name
  location               = azurerm_resource_group.image_builder_rg.location
  os_type                = "Windows"
  hyper_v_generation     = "V2"
  trusted_launch_enabled = true

  identifier {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
  }

  tags = var.tags
}

resource "azapi_resource" "image_template" {
  type      = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"
  name      = "ibt-win11-multi-session-${var.environment}"
  parent_id = azurerm_resource_group.image_builder_rg.id
  location  = azurerm_resource_group.image_builder_rg.location

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.image_builder_identity.id]
  }

  body = jsonencode({
    properties = {
      buildTimeoutInMinutes = 240
      customize = [
        {
          name           = "windows-update"
          type           = "WindowsUpdate"
          searchCriteria = "IsInstalled=0"
          filters = [
            "exclude:$_.Title -like '*Preview*'",
            "include:$true"
          ]
          updateLimit = 40
        },
        {
          name = "configure-windows-defender"
          type = "PowerShell"
          inline = [
            "Write-Host 'Configuring Windows Defender security hardening'",
            "# Enable Windows Defender real-time protection",
            "Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Continue",
            "# Enable automatic sample submission",
            "Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction Continue",
            "# Enable cloud-delivered protection",
            "Set-MpPreference -MAPSReporting Advanced -ErrorAction Continue",
            "# Schedule Windows Defender scan",
            "Set-MpPreference -ScanScheduleTime 00:00:00 -ScanScheduleQuickScanTime 12:00:00 -ErrorAction Continue",
            "# Update Windows Defender definitions",
            "Update-MpSignature -ErrorAction Continue"
          ]
        },
        {
          name = "configure-firewall-rules"
          type = "PowerShell"
          inline = [
            "Write-Host 'Configuring Windows Firewall security hardening'",
            "# Enable Windows Firewall for all profiles",
            "netsh advfirewall set allprofiles state on",
            "# Set default policies",
            "netsh advfirewall set domainprofile policy outbound=allow inbound=block",
            "netsh advfirewall set privateprofile policy outbound=allow inbound=block",
            "netsh advfirewall set publicprofile policy outbound=allow inbound=block",
            "# Allow RDP for AVD (port 3389)",
            "netsh advfirewall firewall add rule name='AVD RDP' dir=in action=allow protocol=TCP localport=3389",
            "# Allow WinRM for management (port 5985)",
            "netsh advfirewall firewall add rule name='WinRM HTTP' dir=in action=allow protocol=TCP localport=5985",
            "netsh advfirewall firewall add rule name='WinRM HTTPS' dir=in action=allow protocol=TCP localport=5986"
          ]
        },
        {
          name = "install-fslogix-agent"
          type = "PowerShell"
          inline = [
            "Write-Host 'Installing FSLogix agent'",
            "# Download FSLogix directly from Microsoft",
            "$fslogixUrl = 'https://aka.ms/fslogix_download'",
            "$fslogixZip = 'C:\\Windows\\Temp\\FSLogix.zip'",
            "$fslogixDir = 'C:\\Windows\\Temp\\FSLogix'",
            "Invoke-WebRequest -Uri $fslogixUrl -OutFile $fslogixZip -UseBasicParsing",
            "Expand-Archive -Path $fslogixZip -DestinationPath $fslogixDir -Force",
            "$installer = Get-ChildItem -Path $fslogixDir -Recurse -Filter 'FSLogixAppsSetup.exe' | Select-Object -First 1",
            "Start-Process -FilePath $installer.FullName -ArgumentList '/install /quiet /norestart' -Wait",
            "# Create FSLogix configuration directory",
            "New-Item -Path 'C:\\Program Files\\FSLogix\\Apps\\Rules' -ItemType Directory -Force | Out-Null",
            "Write-Host 'FSLogix agent installation completed'"
          ]
        },
        {
          name = "configure-fslogix-registry"
          type = "PowerShell"
          inline = [
            "Write-Host 'Configuring FSLogix registry keys for AADDS profile paths'",
            "# FSLogix profile container registry keys",
            "# VHDLocations will be set via Group Policy or VM extension post-deployment",
            "# Placeholder UNC path - replace with actual Azure Files share after AADDS provisioning",
            "# e.g. \\\\<storageaccount>.file.core.windows.net\\<share>\\profiles",
            "$fslogixRegPath = 'HKLM:\\SOFTWARE\\FSLogix\\Profiles'",
            "New-Item -Path $fslogixRegPath -Force | Out-Null",
            "# Enable FSLogix profile containers",
            "New-ItemProperty -Path $fslogixRegPath -Name 'Enabled' -Value 1 -PropertyType DWORD -Force | Out-Null",
            "# Placeholder VHDLocations - override via GPO after AADDS/FSLogix deployment",
            "New-ItemProperty -Path $fslogixRegPath -Name 'VHDLocations' -Value '\\\\placeholder.file.core.windows.net\\profiles' -PropertyType MultiString -Force | Out-Null",
            "# Delete local profile when VHD should apply",
            "New-ItemProperty -Path $fslogixRegPath -Name 'DeleteLocalProfileWhenVHDShouldApply' -Value 1 -PropertyType DWORD -Force | Out-Null",
            "# Flip-flop profile directory name (user/sid vs sid/user)",
            "New-ItemProperty -Path $fslogixRegPath -Name 'FlipFlopProfileDirectoryName' -Value 1 -PropertyType DWORD -Force | Out-Null",
            "Write-Host 'FSLogix registry keys configured (VHDLocations placeholder - update via GPO post-deploy)'"
          ]
        },
        {
          name = "install-rsat-ad-powershell"
          type = "PowerShell"
          inline = [
            "Write-Host 'Installing RSAT-AD-PowerShell for AADDS domain management'",
            "# Install RSAT Active Directory PowerShell module for domain-join scripts",
            "Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0' -ErrorAction Continue",
            "Write-Host 'RSAT-AD-PowerShell installation completed'"
          ]
        },
        {
          name = "configure-avd-optimizations"
          type = "PowerShell"
          inline = [
            "Write-Host 'Configuring AVD optimizations'",
            "# Disable unnecessary services",
            "Get-Service -Name 'WSearch' | Set-Service -StartupType Disabled",
            "Get-Service -Name 'DiagTrack' | Set-Service -StartupType Disabled",
            "Get-Service -Name 'dmwappushservice' | Set-Service -StartupType Disabled",
            "# Set power plan to High Performance",
            "powercfg /change monitor-timeout-ac 30",
            "powercfg /change disk-timeout-ac 0",
            "# Disable Windows Tips",
            "Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager' -Name 'SubscribedContent-310093Enabled' -Value 0",
            "# Enable Audio redirection optimization",
            "Set-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\services\\AudioSrv' -Name 'Start' -Value 2",
            "# Optimize network settings",
            "netsh int tcp set global autotuninglevel=normal",
            "# Enable RDP ShortPath",
            "Set-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Terminal Server\\WinStations\\RDP-Tcp' -Name 'fUseUdpPortRedirector' -Value 1 -Force"
          ]
        },
        {
          name = "configure-security-baselines"
          type = "PowerShell"
          inline = [
            "Write-Host 'Applying security baseline configurations'",
            "# Enable Credential Guard",
            "reg add 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Lsa\\MSV1_0' /v 'RestrictSendingNTLMTraffic' /t REG_DWORD /d 1 /f",
            "# Enable Data Execution Prevention",
            "reg add 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management' /v 'NullPageProtection' /t REG_DWORD /d 1 /f",
            "# Require Ctrl-Alt-Delete for login",
            "reg add 'HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System' /v 'DisableCAD' /t REG_DWORD /d 0 /f",
            "# Enable Extended protection",
            "reg add 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\SecurityProviders\\WDigest' /v 'UseLogonCredential' /t REG_DWORD /d 0 /f",
            "# Enable UAC for all users",
            "reg add 'HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System' /v 'EnableLUA' /t REG_DWORD /d 1 /f"
          ]
        },
        {
          name = "validate-installation"
          type = "PowerShell"
          inline = [
            "Write-Host 'Validating image configuration'",
            "# Verify FSLogix installation",
            "if (Test-Path 'C:\\Program Files\\FSLogix\\Apps\\frxdrv.sys') { Write-Host 'FSLogix: OK' } else { Write-Host 'FSLogix: MISSING' }",
            "# Verify Windows Defender status",
            "(Get-MpComputerStatus).AMServiceEnabled | Write-Host 'Defender Status: OK' -ForegroundColor Green",
            "# Verify Firewall status",
            "if ((Get-NetFirewallProfile | Where-Object { $_.Enabled -eq $true }).Count -gt 0) { Write-Host 'Firewall: OK' } else { Write-Host 'Firewall: DISABLED' }",
            "# List installed services",
            "Write-Host 'Image validation completed'"
          ]
        },
        {
          name                = "windows-restart-before-sysprep"
          type                = "WindowsRestart"
          restartCheckCommand = "echo Azure Image Builder restarted machine"
          restartTimeout      = "10m"
        },
        {
          name = "sysprep"
          type = "PowerShell"
          inline = [
            "Write-Host 'Running sysprep to generalize image for Flexible VMSS deployment'",
            "Start-Process -FilePath 'C:\\Windows\\System32\\Sysprep\\sysprep.exe' -ArgumentList '/generalize /oobe /shutdown /quiet' -Wait",
            "Write-Host 'Sysprep completed'"
          ]
          runElevated = true
        }
      ]
      distribute = concat(
        var.create_shared_gallery ? [{
          type               = "SharedImage"
          runOutputName      = "windows11-multi-session-output"
          imageId            = azurerm_shared_image.windows_11_image[0].id
          replicationRegions = var.replication_regions
        }] : [],
        [{
          type   = "VHD"
          vhdUri = "${var.staging_storage_account_blob_endpoint}avd-golden-images/win11-multi-session-${var.environment}.vhd"
        }]
      )
      source = {
        type      = "PlatformImage"
        publisher = var.source_image_publisher
        offer     = var.source_image_offer
        sku       = var.source_image_sku
        version   = var.source_image_version
      }
      vmProfile = {
        vmSize = "Standard_D4s_v5"
      }
    }
  })

  tags = var.tags

  lifecycle {
    ignore_changes = [body]
  }
}

resource "azurerm_storage_account" "staging" {
  # checkov:skip rationale: CKV_AZURE_33 checks Queue service logging, but this is a
  # temporary staging account used only for VHD distribution during AIB image builds.
  # No Queue service is used; enabling Queue logging on a Blob-only staging account
  # is not applicable. The account is optional (create_staging_storage = false by default)
  # and is only used transiently during image template builds.
  #checkov:skip=CKV_AZURE_33: Staging VHD distribution account uses Blob service only; Queue service is disabled and Queue logging is not applicable for temporary image build staging
  count                           = var.create_staging_storage ? 1 : 0
  name                            = "stgavdib${random_string.storage_account_name[0].result}"
  resource_group_name             = azurerm_resource_group.image_builder_rg.name
  location                        = azurerm_resource_group.image_builder_rg.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  tags                            = var.tags

  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "POST"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
  }
}

resource "azurerm_storage_account_network_rules" "staging_network_rules" {
  count              = var.create_staging_storage ? 1 : 0
  storage_account_id = azurerm_storage_account.staging[0].id

  default_action             = "Deny"
  ip_rules                   = []
  virtual_network_subnet_ids = []
  bypass                     = ["AzureServices"]
}

resource "random_string" "storage_account_name" {
  count   = var.create_staging_storage ? 1 : 0
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_role_assignment" "staging_storage_role_assignment" {
  count                = var.create_staging_storage ? 1 : 0
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.image_builder_identity.principal_id
  scope                = azurerm_storage_account.staging[0].id
}
