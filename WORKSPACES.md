# OpenTofu Workspaces and Deployment Guide

This project uses a **layered root module** architecture. Each layer is an independent
OpenTofu root configuration with its own remote backend state file.

> **Critical**: Environment directories (`environments/shared/`, `environments/dedicated/`)
> contain `terraform { backend {} }` blocks. They **cannot** be called as child modules from
> a parent `main.tf`. Each must be deployed independently with `tofu init && tofu apply`.

---

## Root Modules (Workspaces)

| Step | Directory | State Key | Description | Prerequisites |
|------|-----------|-----------|-------------|--------------|
| 1 | `bootstrap/` | `bootstrap` (local) | State storage account, hub VNet, Azure Firewall, Private DNS Zones, Management Groups, Azure Policy, Defender for Cloud, OIDC role assignment | Azure subscription + Owner/Contributor |
| 2 | `networking/hub-and-spoke/` | `networking/hub-and-spoke` | Hub-and-spoke VNet topology, NSGs, firewall rules, AADDS subnet, Private DNS Zone VNet links | `bootstrap/` completed; `backend.hcl` populated |
| 3 | `imaging/image-builder/` | `imaging/image-builder` | Azure Image Builder golden image pipeline, Shared Image Gallery | `bootstrap/` completed; `backend.hcl` populated |
| 4 | `environments/shared/` | `environments/shared` | Shared multi-tenant AVD: AADDS, networking, FSLogix, AVD control plane, session hosts | Steps 1–2 completed; AADDS DNS IPs available for second pass |
| 5 | `environments/dedicated/` | `environments/dedicated` | Per-customer dedicated AVD: isolated VNet, Personal host pool, FSLogix, hub peering | Steps 1–2 completed |

Each of these is initialized and applied independently. Remote state is stored in the Azure
Blob Storage account created by `bootstrap/`, using the key paths shown above.

---

## Step-by-Step Deployment

### Step 1: Bootstrap (Run Once)

The bootstrap layer creates all shared platform infrastructure including the remote state backend.

```bash
cd bootstrap
tofu init       # Uses local state (no backend config needed for bootstrap itself)
tofu plan -var="oidc_sp_app_id=<app-id>" -var="oidc_sp_object_id=<object-id>"
tofu apply -var="oidc_sp_app_id=<app-id>" -var="oidc_sp_object_id=<object-id>"
```

Note the outputs — you will need them to populate `backend.hcl`:

```bash
tofu output backend_config    # Sensitive — shows storage account name and container
tofu output hub_vnet_id
tofu output firewall_private_ip
tofu output private_dns_zone_ids
```

Populate the shared `backend.hcl` at the repo root:

```hcl
resource_group_name  = "rg-tfstate-prod"
storage_account_name = "tfstatestorage"    # from bootstrap output
container_name       = "tfstate"
use_oidc             = true
```

### Step 2: Hub-and-Spoke Networking

```bash
cd networking/hub-and-spoke
tofu init -backend-config=../../backend.hcl
tofu plan
tofu apply
```

**First-time note**: If AADDS has not been deployed yet, leave `aadds_dns_server_ips = []`
(the default). You will re-apply this layer after AADDS is running to inject the DNS IPs.

Key outputs to record for later layers:

```bash
tofu output hub_vnet_id
tofu output hub_aadds_subnet_id
tofu output firewall_private_ip    # Used for UDR in dedicated environments
tofu output private_dns_zone_ids   # Used for private endpoint DNS registration
```

### Step 3: Image Builder (Optional — Can Run Any Time)

The image builder is independent of the environment layers. Build the golden image before
deploying session hosts, or update it at any time without impacting running sessions.

```bash
cd imaging/image-builder
tofu init -backend-config=../../backend.hcl
tofu plan
tofu apply
```

After apply, trigger the image build:

```bash
# Get the image template name from output
IMAGE_TEMPLATE=$(tofu output -raw image_template_name)
RG="rg-avd-imaging-prod"    # adjust to your value

# Start the build (takes ~60–90 minutes)
az image builder run \
  --name "$IMAGE_TEMPLATE" \
  --resource-group "$RG"

# Monitor build status
az image builder show \
  --name "$IMAGE_TEMPLATE" \
  --resource-group "$RG" \
  --query "lastRunStatus"
```

See [docs/runbook-image-update.md](docs/runbook-image-update.md) for full image update procedure.

### Step 4: Shared Environment (Two-Pass)

The shared environment includes AADDS. Because AADDS domain controller IPs are computed
at apply time, this layer requires **two apply passes**.

**Pass 1 — Deploy AADDS and everything else (DNS servers will be `null` initially):**

```bash
cd environments/shared
tofu init -backend-config=../../backend.hcl
tofu plan
tofu apply
```

After pass 1, note the AADDS domain controller IPs:

```bash
tofu output aadds_domain_controller_ips    # e.g., ["10.0.5.4", "10.0.5.5"]
```

**Pass 2 — Re-apply networking with AADDS DNS IPs:**

Update the `aadds_dns_server_ips` variable in `networking/hub-and-spoke/variables.tf`
default or pass it directly:

```bash
cd networking/hub-and-spoke
tofu apply -var='aadds_dns_server_ips=["10.0.5.4","10.0.5.5"]'
cd ../..
```

Then re-apply the shared environment to pick up the DNS configuration:

```bash
cd environments/shared
tofu apply
```

### Step 5: Dedicated Environment

The dedicated environment is deployed once and extended by adding new `module` blocks
in `environments/dedicated/customer-example.tf` for each customer.

```bash
cd environments/dedicated
tofu init -backend-config=../../backend.hcl
tofu plan
tofu apply
```

To add a new dedicated customer, see [docs/runbook-add-customer.md](docs/runbook-add-customer.md).

---

## State File Layout

All non-bootstrap state files live in the `tfstate` container of the bootstrap storage account:

```
tfstate/
├── bootstrap                       # bootstrap/ state (local during bootstrap, then migrate)
├── networking/hub-and-spoke        # networking/hub-and-spoke/ state
├── imaging/image-builder           # imaging/image-builder/ state
├── environments/shared             # environments/shared/ state
└── environments/dedicated          # environments/dedicated/ state
```

State locking is automatic via Azure Blob Storage lease semantics. No additional
configuration is required.

---

## OpenTofu Workspaces

> **Note**: OpenTofu named workspaces (e.g., `tofu workspace new shared`) are **not** used in
> this project. State isolation is achieved through separate root modules with unique `key`
> values in each `backend.hcl`. This is more explicit and avoids confusion about which
> workspace applies to which layer.

If you need to work on multiple deployment targets of the same root (e.g., deploying the
dedicated environment into two different Azure subscriptions), use different backend configs
rather than workspaces.

---

## State Locking

State locking is automatically enabled with Azure Blob Storage. During plan/apply:
- The state blob is leased (locked) for the duration of the operation.
- Concurrent operations will fail with a lock error and display the lock holder's identity.
- Locks expire automatically after 15 minutes of inactivity.

To break a stuck lock:

```bash
az storage blob lease break \
  --container-name tfstate \
  --blob-name environments/shared \
  --account-name tfstatestorage
```

---

## Troubleshooting

### Backend initialisation fails

```
Error: Failed to get existing workspaces: ... 403 Forbidden
```

The OIDC service principal does not have `Storage Blob Data Contributor` on the state storage
account. Verify the role assignment created by bootstrap:

```bash
az role assignment list \
  --scope "$(az storage account show -g rg-tfstate-prod -n tfstatestorage --query id -o tsv)" \
  --query "[?roleDefinitionName=='Storage Blob Data Contributor']"
```

### AADDS provisioning takes a long time

AADDS typically takes 45–60 minutes to provision on first deployment. This is normal. The
`tofu apply` will wait for the resource to reach a running state.

### Session hosts fail domain join

Verify that:
1. The spoke VNet's DNS servers point to the AADDS domain controller IPs (second-pass apply completed).
2. The AADDS subnet NSG allows TCP/UDP 389, 636, 88, 53, and TCP 443/5986 from `AzureActiveDirectoryDomainServices`.
3. The session host subnet can reach the AADDS subnet (check VNet peering + firewall rules).
