# Remote State Backend Configuration for Hub-and-Spoke Networking
# Use with: tofu init -backend-config=backend.hcl
#
# This root module manages all hub and static spoke VNets for the platform
# networking layer. It must be deployed independently from workload modules.
#
# Deploy order:
#   1. bootstrap/        - creates state storage, management groups
#   2. networking/hub-and-spoke/  (this module)
#   3. environments/shared/
#   4. environments/dedicated/

resource_group_name  = "rg-tfstate-prod"
storage_account_name = "tfstatestorage"
container_name       = "tfstate"
key                  = "networking/hub-and-spoke"
use_oidc             = true
