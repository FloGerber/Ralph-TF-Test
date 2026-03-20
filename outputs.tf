# Root outputs — stub only.
# Outputs for each environment are exposed by their own root module when deployed
# independently. See WORKSPACES.md for the layered deployment order.

# NOTE: Outputs for shared_hosting and dedicated_hosting have been removed because
# environments/shared and environments/dedicated are root configurations with their
# own backends and cannot be called as child modules from this root.
# Each environment layer exposes its own outputs when deployed independently.
# See WORKSPACES.md for the layered deployment order.
