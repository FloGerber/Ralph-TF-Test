# Remote State Backend Configuration
# Use with: tofu init -backend-config=backend.hcl
#
# This configuration uses workspaces for environment isolation:
# - default workspace -> shared environment
# - dedicated workspace -> dedicated environment
#
# State locking is automatically enabled with Azure Blob Storage

resource_group_name  = "rg-tfstate-prod"
storage_account_name = "tfstatestorage"
container_name       = "tfstate"
use_oidc             = true
