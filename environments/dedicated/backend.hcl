# Remote State Backend Configuration for Dedicated Customer Environments
# Use with: tofu init -backend-config=backend.hcl
#
# This root module manages all dedicated per-customer AVD environments.
# Each customer is represented by a module block in customer-example.tf (or a
# dedicated customer-<name>.tf file). All dedicated customers share a single
# state file under this key.
#
# Deploy order:
#   1. bootstrap/                         - creates state storage, management groups
#   2. networking/hub-and-spoke/          - hub VNet, firewall, Private DNS Zones
#   3. environments/shared/               - shared AADDS, FSLogix, AVD host pools
#   4. environments/dedicated/  (this)    - per-customer dedicated environments

resource_group_name  = "rg-tfstate-prod"
storage_account_name = "tfstatestorage"
container_name       = "tfstate"
key                  = "environments/dedicated"
use_oidc             = true
