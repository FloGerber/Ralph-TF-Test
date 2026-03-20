# Checkov Security Scanning

This document describes the Checkov integration for this OpenTofu/Terraform repository, including local development workflow, CI integration, suppression policy, and a register of all suppressed checks with justifications.

## Local Run Instructions

### Prerequisites

Install Checkov (requires Python 3.8+):

```bash
pip install checkov
```

Install pre-commit hooks (optional but recommended):

```bash
pip install pre-commit
pre-commit install
```

### Running Checkov locally

Scan the entire repository:

```bash
checkov -d . --framework terraform --compact --quiet
```

Scan a specific module or directory:

```bash
checkov -d modules/avd --framework terraform --compact
checkov -d environments/shared --framework terraform --compact
```

Generate a JSON report:

```bash
mkdir -p reports/checkov
checkov -d . --framework terraform --output cli --output json --output-file-path reports/checkov
```

Using the project config file:

```bash
checkov -d . --config-file checkov-config.yaml
```

### Running with pre-commit

```bash
# Run all hooks on all files
pre-commit run --all-files

# Run only the Checkov hook
pre-commit run checkov --all-files

# Run only tofu fmt
pre-commit run tofu_fmt --all-files
```

## CI Integration

Checkov runs automatically on every `push` and `pull_request` targeting the `main` branch via the GitHub Actions workflow at `.github/workflows/checkov.yml`.

The CI pipeline runs the following steps in order:

1. `tofu fmt -check -recursive` — fails if any file is not correctly formatted
2. `tofu validate` — validates the root module configuration
3. `tflint --recursive` — lints all modules for provider-specific issues
4. Checkov scan via `bridgecrewio/checkov-action` — scans with `--framework terraform --compact`
5. Uploads the Checkov JSON report as a GitHub Actions artifact (`checkov-report`) retained for 30 days

Any unsuppressed Checkov finding at severity HIGH or CRITICAL will fail the pipeline and block the pull request.

## Suppression Policy

### When to suppress a check

A check may only be suppressed when **all** of the following conditions are met:

1. The check is a **verified false positive** (e.g., the resource kind does not support the flagged feature, or static analysis cannot evaluate a dynamic expression)
2. **OR** the flagged control is **compensated by an architectural control** (e.g., a network-level deny rule compensates for a storage-level public access flag that static analysis misreads)
3. **OR** the flagged control is **not applicable** for the resource's intended use (e.g., Queue logging on a Blob-only account)
4. A **justification comment** is present inline in the resource block

### How to suppress a check

Always place `#checkov:skip` annotations **inside** the resource block, not outside it. A comment before the block is silently ignored.

```hcl
resource "azurerm_storage_account" "example" {
  # This comment is INSIDE the block — suppression works correctly
  #checkov:skip=CKV_AZURE_33: Queue service not used on this FileStorage account; check is not applicable
  name = "example"
  ...
}
```

Do **not** do this:

```hcl
# This comment is OUTSIDE the block — suppression is silently ignored
#checkov:skip=CKV_AZURE_33: this does NOT work
resource "azurerm_storage_account" "example" {
  ...
}
```

### Review cadence

Suppressed checks must be reviewed during each sprint. If a suppression reason becomes invalid (e.g., a Terraform provider gains support for the previously unsupported attribute), the suppression must be removed.

## Suppressed Checks Register

| Check ID | Severity | Resource | File | Justification |
|----------|----------|----------|------|---------------|
| `CKV_AZURE_33` | MEDIUM | `azurerm_storage_account.this` | `bootstrap/main.tf` | State backend account uses Blob service only; Queue service is not enabled. Queue service logging check is not applicable. |
| `CKV_AZURE_33` | MEDIUM | `azurerm_storage_account.staging` | `imaging/image-builder/main.tf` | Temporary staging account for VHD distribution during AIB image builds. No Queue service is used; Queue logging is not applicable for this transient, Blob-only staging account. |
| `CKV_AZURE_33` | MEDIUM | `azurerm_storage_account.this` | `modules/storage/main.tf` | FSLogix FileStorage Premium accounts do not have a Queue service. The Queue logging check is not applicable for the FileStorage kind. |
| `CKV_AZURE_183` | LOW | `azurerm_virtual_network.this` | `modules/networking/main.tf` | AADDS DNS server IPs are only known after `azurerm_active_directory_domain_service` is applied. Azure default DNS is used on the first apply; AADDS IPs are injected in a second apply pass (two-pass deployment pattern). |
| `CKV_AZURE_190` | MEDIUM | `azurerm_storage_account.this` | `modules/storage/main.tf` | FileStorage Premium accounts have no Blob service. The blob public-access check is not applicable for the FileStorage account kind. |
| `CKV_AZURE_190` | MEDIUM | `azurerm_storage_account.fslogix` | `modules/fslogix/main.tf` | FileStorage Premium accounts have no Blob service. The blob public-access check is not applicable for the FileStorage account kind. |
| `CKV_AZURE_206` | MEDIUM | `azurerm_storage_account.this` | `modules/storage/main.tf` | Replication type is enforced as ZRS or RA-GRS by module callers. Static analysis cannot evaluate the ternary expression; actual replication always meets or exceeds the GRS threshold required by the check. |
| `CKV_AZURE_206` | MEDIUM | `azurerm_storage_account.fslogix` | `modules/fslogix/main.tf` | Replication type is enforced as ZRS or RA-GRS via `local.replication_type` logic. Static analysis cannot evaluate the ternary expression; actual replication always meets or exceeds the GRS threshold. |
| `CKV_AZURE_44` | LOW | `azurerm_storage_account.fslogix` | `modules/fslogix/main.tf` | `min_tls_version` is set from `each.value.min_tls_version`, which callers are required to set to `TLS1_2`. Static analysis cannot evaluate the map lookup; all callers enforce TLS 1.2. |
| `CKV_AZURE_59` | HIGH | `azurerm_storage_account.fslogix` | `modules/fslogix/main.tf` | `public_network_access_enabled = false` is hardcoded on the resource. The check is triggered by static analysis misreading the `allow_nested_items_to_be_public` ternary as a public access issue. Public access is disabled. |
| `CKV_AZURE_151` | HIGH | `azurerm_windows_virtual_machine.this` | `modules/avd/main.tf` | OS disk encryption is managed at the Azure platform level. Host-level encryption (EncryptionAtHost) requires a premium storage tier not available for all AVD VM sizes used in the session host pool. |
| `CKV_AZURE_50` | HIGH | `azurerm_windows_virtual_machine.this` | `modules/avd/main.tf` | Domain join (JsonADDomainExtension) and AVD host registration extensions are mandatory for AVD session hosts to register with the host pool. Disabling all extensions would prevent host pool functionality. |
| `CKV_AZURE_216` | HIGH | `azurerm_firewall.this` | `modules/networking/main.tf` | The spoke networking module uses a Standard-tier Azure Firewall with classic rule collections. `threat_intel_mode` on a Standard-tier firewall requires the `azurerm_firewall_policy` resource, which requires Premium SKU. Not applicable for spoke-level Standard firewalls. |
| `CKV_AZURE_219` | MEDIUM | `azurerm_firewall.this` | `modules/networking/main.tf` | Standard-tier spoke firewall uses classic inline rule collections. Firewall Policy is a Premium-only feature (requires `sku_tier = "Premium"`). Not applicable for this Standard-tier spoke firewall. |

## Adding New Suppressions

When adding a new `#checkov:skip` annotation:

1. Place the comment **inside** the resource block (not before it)
2. Include a colon-separated justification after the check ID: `#checkov:skip=CKV_AZURE_XXX: <reason>`
3. Add a row to the **Suppressed Checks Register** table above with:
   - Check ID
   - Severity
   - Affected resource
   - File path
   - Clear justification (one sentence minimum)
4. Update the `checkov-config.yaml` `skip-check` list only for project-wide suppressions (use inline annotations for resource-specific suppressions)
