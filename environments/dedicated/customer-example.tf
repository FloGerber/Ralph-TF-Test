# -----------------------------------------------------------------------------
# environments/dedicated/customer-example.tf
#
# Example dedicated-customer module block for "contoso".
# Copy this file, rename it (e.g. customer-<name>.tf), and fill in the
# placeholder values to onboard a new customer with an isolated AVD environment.
#
# Prerequisites:
#   - networking/hub-and-spoke applied  (provides hub_vnet_id, hub_firewall_private_ip)
#   - environments/shared applied       (provides aadds_domain_controller_ips)
#   - imaging/image-builder AIB run completed (provides avd_image_id)
# -----------------------------------------------------------------------------

module "dedicated_customer_contoso" {
  source = "../../modules/dedicated"

  customer_name = "contoso"
  location      = local.location
  tags          = local.tags
  user_count    = 10

  # Golden image ID produced by the AIB pipeline (imaging/image-builder).
  # Set to the Shared Image Gallery image version ID after the first AIB run.
  avd_image_id = ""

  vnet_config = local.vnet_config
  nsg_rules   = local.nsg_rules

  storage_account_config = local.storage_accounts
  file_shares            = local.file_shares

  host_pool_config           = local.host_pool_config
  workspace_config           = local.workspace_config
  application_group_config   = local.application_group_config
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  # ---------------------------------------------------------------------------
  # Hub connectivity — values come from networking/hub-and-spoke outputs.
  # Run: tofu -chdir=networking/hub-and-spoke output hub_vnet_id
  #       tofu -chdir=networking/hub-and-spoke output firewall_private_ip
  # ---------------------------------------------------------------------------
  hub_vnet_id             = "" # e.g. "/subscriptions/<sub>/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
  hub_vnet_name           = "" # e.g. "vnet-hub"
  hub_firewall_private_ip = "" # e.g. "10.0.1.4"

  # ---------------------------------------------------------------------------
  # AADDS DNS servers — only known after AADDS is deployed (second apply pass).
  # Run: tofu -chdir=environments/shared output aadds_domain_controller_ips
  # On first apply, leave as empty list; update and re-apply after AADDS is up.
  # ---------------------------------------------------------------------------
  aadds_dns_servers = [] # e.g. ["10.0.5.4", "10.0.5.5"]

  # ---------------------------------------------------------------------------
  # Domain join — credentials for joining session hosts to the AADDS domain.
  # Store the password in a secret store; do NOT commit plaintext credentials.
  # ---------------------------------------------------------------------------
  # domain_join_config = {
  #   domain   = "contoso.local"
  #   ou_path  = "OU=AVD,DC=contoso,DC=local"
  #   username = "svc-avd-join@contoso.local"
  #   password = var.domain_join_password   # pass as a variable from CI/CD
  # }

  # ---------------------------------------------------------------------------
  # FSLogix profile container — wires session hosts to the Azure Files share.
  # ---------------------------------------------------------------------------
  # fslogix_config = {
  #   storage_account_name = module.dedicated_customer_contoso.storage_account_names[0]
  #   file_share_name      = "profiles"
  #   storage_account_key  = "<key>"   # use Key Vault reference in production
  # }
}
