# Runbook: Golden Image Update

This runbook describes how to trigger a new golden image build via Azure Image Builder (AIB)
and roll out the updated image to AVD session hosts.

---

## Overview

The golden image pipeline:

1. **Azure Image Builder** (`imaging/image-builder/`) builds a Windows 11 23H2 multi-session
   image from the Azure Marketplace, applies customisations (FSLogix, security baselines,
   Windows Updates, sysprep), and stores the resulting image version in an **Azure Shared
   Image Gallery** (`sig-avd-<env>`).

2. **AVD session hosts** reference the gallery image ID via the `avd_image_id` variable in each
   environment. Rolling out a new image requires updating this variable and re-running
   `tofu apply` to trigger VMSS reimaging.

---

## Prerequisites

- OpenTofu >= 1.6
- Azure CLI authenticated with Contributor rights on the imaging resource group
- The image template resource name (from `tofu output image_template_name`)
- A maintenance window scheduled (image builds take 60–90 minutes; session host rollout may require draining)

---

## Step 1: Review Customisation Changes (If Any)

The image customisation steps live in `imaging/image-builder/main.tf` within the
`azapi_resource.image_template` `customize` block. Review or modify as needed before building.

Common changes:

| Change | Location in `main.tf` | Notes |
|--------|----------------------|-------|
| Add new Windows Update policy | `customize` block, `WindowsUpdate` step | Runs via native Windows Update API |
| Install a new application | Add a new `PowerShell` customizer step before sysprep | Use `Invoke-WebRequest` or `Add-WindowsCapability`; avoid Chocolatey |
| Update FSLogix registry keys | `configure-fslogix-registry` PowerShell step | Set `VHDLocations` placeholder; real value injected via GPO |
| Change base image version | `source.version` variable (or `"latest"`) | `"latest"` always picks the most recent marketplace image |
| Add/remove a restart step | `WindowsRestart` customizer before sysprep | Required when installing drivers or features that need a reboot |

After changes, verify the template is valid:

```bash
cd imaging/image-builder
tofu fmt -check
tofu validate
```

---

## Step 2: Apply Infrastructure Changes (If Modified)

If you modified `main.tf`, apply the image builder infrastructure to update the image template
definition. **This does not start a build.**

```bash
cd imaging/image-builder
tofu init -backend-config=../../backend.hcl
tofu plan
tofu apply
```

---

## Step 3: Start the Image Build

Trigger the AIB image build via Azure CLI. This will create a new image version in the
Shared Image Gallery.

```bash
# Get the image template name and resource group
IMAGE_TEMPLATE=$(tofu output -raw image_template_name)
RG=$(tofu output -raw resource_group_name 2>/dev/null || echo "rg-avd-imaging-prod")

echo "Starting build: $IMAGE_TEMPLATE in $RG"

az image builder run \
  --name "$IMAGE_TEMPLATE" \
  --resource-group "$RG" \
  --no-wait

echo "Build started. Monitor with:"
echo "  az image builder show --name $IMAGE_TEMPLATE --resource-group $RG --query lastRunStatus"
```

> **Note**: `--no-wait` returns immediately. The build runs asynchronously and takes
> **60–90 minutes** for a full Windows 11 image with all customisations.

---

## Step 4: Monitor the Build

```bash
# Check build status (poll every few minutes)
watch -n 60 "az image builder show \
  --name '$IMAGE_TEMPLATE' \
  --resource-group '$RG' \
  --query 'lastRunStatus' \
  -o table"
```

Expected `runState` progression: `Running` → `Succeeded`

If the build fails (`runState: Failed`), check the build log:

```bash
# Get the build log storage URL
az image builder show \
  --name "$IMAGE_TEMPLATE" \
  --resource-group "$RG" \
  --query "lastRunStatus.message" \
  -o tsv
```

The error message will include a link to the build log in the staging storage account
(`customization.log`). Download and review:

```bash
# List staging storage accounts (they have a random suffix)
az storage account list \
  --resource-group "$RG" \
  --query "[?starts_with(name,'stgavdib')].name" \
  -o tsv
```

---

## Step 5: Retrieve the New Image Version ID

After a successful build, find the new image version in the Shared Image Gallery:

```bash
GALLERY_NAME=$(tofu output -raw shared_image_gallery_name 2>/dev/null || echo "sig-avd-prod")
IMAGE_NAME=$(tofu output -raw gallery_image_name 2>/dev/null || echo "img-win11-multi-session-prod")

# List all versions (newest last)
az sig image-version list \
  --resource-group "$RG" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition "$IMAGE_NAME" \
  --query "[].{version:name, state:provisioningState, date:publishingProfile.publishedDate}" \
  -o table

# Get the latest version ID
az sig image-version list \
  --resource-group "$RG" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition "$IMAGE_NAME" \
  --query "[-1].id" \
  -o tsv
```

Alternatively, use the Terraform output if it was updated:

```bash
cd imaging/image-builder
tofu output gallery_image_id
```

---

## Step 6: Update the Session Host Image Reference

The session host VMSS in each environment references the gallery image via a variable.
Update the `avd_image_id` variable in the relevant environment.

### Shared Environment

In `environments/shared/locals.tf`, update the image ID passed to the AVD module:

```hcl
# Before:
avd_image_id = "/subscriptions/.../galleries/sig-avd-prod/images/img-win11-multi-session-prod/versions/1.0.0"

# After (new version):
avd_image_id = "/subscriptions/.../galleries/sig-avd-prod/images/img-win11-multi-session-prod/versions/1.0.1"
```

Or, to always use the latest version:

```hcl
avd_image_id = "/subscriptions/.../galleries/sig-avd-prod/images/img-win11-multi-session-prod/versions/latest"
```

### Dedicated Environment

Update the `avd_image_id` in each `module "dedicated_customer_*"` block in
`environments/dedicated/customer-example.tf`.

---

## Step 7: Drain Sessions Before Rollout (Recommended for Production)

To avoid disrupting active users, drain sessions from the host pool before re-imaging:

```bash
HOST_POOL="hp-shared-pool"
RG_AVD="rg-avd-shared-prod"

# Set all session hosts to drain mode
az desktopvirtualization sessionhost list \
  --host-pool-name "$HOST_POOL" \
  --resource-group "$RG_AVD" \
  --query "[].name" -o tsv | while read HOST; do
    az desktopvirtualization sessionhost update \
      --host-pool-name "$HOST_POOL" \
      --resource-group "$RG_AVD" \
      --name "$HOST" \
      --allow-new-session false
    echo "Drained: $HOST"
done

# Wait for active sessions to end (check remaining sessions)
az desktopvirtualization usersession list \
  --host-pool-name "$HOST_POOL" \
  --resource-group "$RG_AVD" \
  --query "length(@)" -o tsv
```

---

## Step 8: Apply the Updated Image to Session Hosts

Apply the updated image ID to trigger a rolling reimage of the VMSS:

```bash
# Shared environment
cd environments/shared
tofu init -backend-config=../../backend.hcl
tofu plan   # Verify only the VMSS image reference changes
tofu apply

# Dedicated environment (if applicable)
cd environments/dedicated
tofu init -backend-config=../../backend.hcl
tofu plan
tofu apply
```

OpenTofu will update the VMSS `source_image_id` or `source_image_reference`. Azure will
schedule a rolling reimage of all instances in the scale set using the new image.

### Monitor VMSS Reimage Progress

```bash
VMSS_NAME="vmss-shared-avd-prod"   # adjust to your value
RG_AVD="rg-avd-shared-prod"

az vmss show \
  --name "$VMSS_NAME" \
  --resource-group "$RG_AVD" \
  --query "virtualMachineProfile.storageProfile.imageReference"

# Watch instance status
az vmss list-instances \
  --name "$VMSS_NAME" \
  --resource-group "$RG_AVD" \
  --query "[].{name:name, state:instanceView.statuses[1].displayStatus}" \
  -o table
```

---

## Step 9: Re-enable New Sessions

After the rollout is complete and you have verified new sessions work correctly:

```bash
# Re-enable new sessions on all hosts
az desktopvirtualization sessionhost list \
  --host-pool-name "$HOST_POOL" \
  --resource-group "$RG_AVD" \
  --query "[].name" -o tsv | while read HOST; do
    az desktopvirtualization sessionhost update \
      --host-pool-name "$HOST_POOL" \
      --resource-group "$RG_AVD" \
      --name "$HOST" \
      --allow-new-session true
    echo "Re-enabled: $HOST"
done
```

---

## Step 10: Verify the Rollout

- [ ] All session hosts show as **Available** in the AVD host pool
- [ ] New sessions can be established and receive the updated image
- [ ] FSLogix profiles load correctly (VHD mounts, no errors in Event Viewer)
- [ ] Application launch works end-to-end for a test user in each customer group
- [ ] Old image version can be cleaned up (optional — keep last 2 versions for rollback)

---

## Rollback

If the new image causes issues, roll back by reverting the `avd_image_id` variable to the
previous image version ID and re-running `tofu apply`. The VMSS will reimage back to the
previous version.

```bash
# List available versions to find the previous one
az sig image-version list \
  --resource-group "$RG" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition "$IMAGE_NAME" \
  --query "[].{version:name, date:publishingProfile.publishedDate}" \
  -o table
```

---

## Scheduled Image Updates

For regular monthly updates (recommended to keep Windows Updates current):

1. Set up a scheduled pipeline trigger (e.g., monthly GitHub Actions cron job) that runs:
   - `az image builder run` against the image template
   - Updates the `avd_image_id` variable via a pull request
   - Runs `tofu plan` and creates a PR for human review before apply
2. Use `source.version = "latest"` in the image template to automatically pick up the
   latest Windows 11 marketplace image on each build.
