# Remote State Backend Configuration

## Overview

This project uses Azure Blob Storage for remote state storage with the following features:

- State locking via Azure Blob Storage lease semantics
- Encryption at rest (Microsoft-managed keys, enabled by default)
- Layer-based state isolation (separate state key per root module)
- OIDC federated credential authentication for CI/CD (no long-lived secrets)

---

## OIDC Service Principal Setup

CI/CD pipelines authenticate to Azure using OIDC (federated identity credentials) rather than
long-lived client secrets. You must create the service principal **before** running bootstrap.

### Step 0: Create the OIDC Service Principal

```bash
# Create the app registration
az ad app create --display-name "opentofu-platform-cicd"

# Capture IDs
APP_ID=$(az ad app list --display-name "opentofu-platform-cicd" --query "[0].appId" -o tsv)
SP_OBJ_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || \
            az ad sp create --id "$APP_ID" --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUB_ID=$(az account show --query id -o tsv)
```

### Step 1a: GitHub Actions — Federated Credentials

Add a federated credential for each branch/environment you need to deploy from:

```bash
# Main branch deployments
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "github-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<ORG>/<REPO>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Pull request checks (plan only — no apply)
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "github-actions-pr",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<ORG>/<REPO>:pull_request",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**GitHub Actions workflow configuration:**

```yaml
# .github/workflows/deploy.yml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1

      - name: Tofu Init
        run: tofu init -backend-config=backend.hcl
        working-directory: environments/shared
        env:
          ARM_USE_OIDC: "true"
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Tofu Apply
        run: tofu apply -auto-approve
        working-directory: environments/shared
        env:
          ARM_USE_OIDC: "true"
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

**Required GitHub Actions secrets:**

| Secret | Value |
|--------|-------|
| `AZURE_CLIENT_ID` | App (client) ID of the service principal |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID |

### Step 1b: Azure DevOps — Federated Credentials

Add a federated credential for the Azure DevOps service connection:

```bash
# Get the service connection issuer from Azure DevOps:
# Organization Settings → Service Connections → <connection> → Edit → "Workload Identity federation"
# The subject pattern is: sc://<org>/<project>/<service-connection-name>

az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "azdo-service-connection",
    "issuer": "https://vstoken.dev.azure.com/<YOUR_ADO_ORG_ID>",
    "subject": "sc://<ORG>/<PROJECT>/<SERVICE_CONNECTION_NAME>",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**Azure DevOps pipeline configuration:**

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: ubuntu-latest

variables:
  - group: azure-credentials   # Contains AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID

steps:
  - task: AzureCLI@2
    displayName: 'Tofu Init & Apply'
    inputs:
      azureSubscription: '<SERVICE_CONNECTION_NAME>'
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: |
        export ARM_USE_OIDC=true
        export ARM_CLIENT_ID=$(az account show --query user.name -o tsv)
        export ARM_TENANT_ID=$AZURE_TENANT_ID
        export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

        cd environments/shared
        tofu init -backend-config=../../backend.hcl
        tofu apply -auto-approve
      addSpnToEnvironment: true
```

> **Azure DevOps tip**: Use the `azureSubscription` task input to authenticate via the OIDC
> service connection. The `addSpnToEnvironment: true` option injects `$servicePrincipalId`
> and `$idToken` into the environment for use with `ARM_USE_OIDC=true`.

---

## Required Role Assignments

The OpenTofu automation service principal requires the following **minimum** roles to
plan and apply the full platform stack:

| Scope | Role | Purpose |
|-------|------|---------|
| State Storage Account | `Storage Blob Data Contributor` | Read/write OpenTofu remote state blobs |
| Subscription | `Contributor` | Provision and manage all platform resources (VNets, VMs, AVD, Storage, etc.) |
| Subscription | `Role Based Access Control Administrator` (or `User Access Administrator`) | Create `azurerm_role_assignment` resources — required for RBAC assignments on app groups, FSLogix accounts, and session host identities |

> **Least-privilege note**: If `Contributor` + `Role Based Access Control Administrator`
> is too broad for your organization's policy, create a custom role that grants
> `Microsoft.Authorization/roleAssignments/write` and `Microsoft.Authorization/roleAssignments/delete`
> scoped to the relevant resource groups instead of the full subscription.

Assign the subscription-level roles:

```bash
az role assignment create \
  --assignee "$SP_OBJ_ID" \
  --role "Contributor" \
  --scope "/subscriptions/$SUB_ID"

az role assignment create \
  --assignee "$SP_OBJ_ID" \
  --role "Role Based Access Control Administrator" \
  --scope "/subscriptions/$SUB_ID"
```

The bootstrap layer grants `Storage Blob Data Contributor` automatically when you pass
`oidc_sp_object_id` as a variable:

```bash
cd bootstrap
tofu apply \
  -var="oidc_sp_app_id=$APP_ID" \
  -var="oidc_sp_object_id=$SP_OBJ_ID"
```

---

## Setup Instructions

### Step 1: Create State Storage (Bootstrap)

Run the bootstrap configuration to create the storage account:

```bash
cd bootstrap
tofu init
tofu plan
tofu apply \
  -var="oidc_sp_app_id=$APP_ID" \
  -var="oidc_sp_object_id=$SP_OBJ_ID"
```

This creates:

- Resource Group: `rg-tfstate-prod`
- Storage Account: `tfstatestorage` (GRS, TLS 1.2, no public access)
- Blob Container: `tfstate` (private)
- Hub VNet (`vnet-hub-prod`) with subnets: GatewaySubnet, AzureFirewallSubnet, snet-management, snet-frontend, snet-backend
- Azure Firewall (`afw-hub-prod`) with Premium Firewall Policy (Threat Intel: Deny, IDS: Deny)
- Private DNS Zones: `privatelink.file.core.windows.net`, `privatelink.blob.core.windows.net`
- Log Analytics Workspace: `law-bootstrap-prod`
- Management Groups: Landing Zones, Management, Connectivity, Shared, Dedicated
- Azure Policy: CostCenter tag audit
- Microsoft Defender for Cloud: VirtualMachines (Standard tier)
- Role assignment: `Storage Blob Data Contributor` on state storage for the OIDC service principal

### Step 2: Populate `backend.hcl`

```hcl
# backend.hcl (repo root — committed to source control; no secrets here)
resource_group_name  = "rg-tfstate-prod"
storage_account_name = "tfstatestorage"
container_name       = "tfstate"
use_oidc             = true
```

Each root module's `backend.hcl` specifies its own `key`:

```hcl
# networking/hub-and-spoke/backend.hcl
key = "networking/hub-and-spoke"

# environments/shared/backend.hcl (inherit from root, no key override needed — set at init)
key = "environments/shared"
```

### Step 3: Initialize Each Layer

```bash
cd networking/hub-and-spoke
tofu init -backend-config=../../backend.hcl

cd environments/shared
tofu init -backend-config=../../backend.hcl

cd environments/dedicated
tofu init -backend-config=../../backend.hcl
```

---

## Bootstrap Outputs

After `tofu apply` the `oidc_guidance` output (non-sensitive) provides:

- `oidc_sp_app_id` — App (client) ID to use in your CI/CD pipeline configuration
- `required_roles` — Human-readable description of each required role assignment
- `documentation` — Pointer back to this file

```bash
cd bootstrap
tofu output oidc_guidance
```

---

## Backend Configuration Reference

| Parameter | Description |
|-----------|-------------|
| `resource_group_name` | Resource group containing the state storage account |
| `storage_account_name` | Name of the state storage account |
| `container_name` | Blob container name for state files (`tfstate`) |
| `key` | State file path within the container (unique per root module) |
| `use_oidc` | Use OIDC federated credential authentication (recommended) |
| `use_azuread_auth` | Use Azure AD auth for blob operations (set alongside `use_oidc`) |

---

## State Locking

Azure Blob Storage provides built-in state locking:

- Automatically locks during plan/apply operations
- Prevents concurrent modifications to the same state file
- Lock expires after 15 minutes of inactivity

To break a stuck lock:

```bash
az storage blob lease break \
  --container-name tfstate \
  --blob-name environments/shared \
  --account-name tfstatestorage
```

---

## Troubleshooting

### 403 Forbidden on `tofu init`

The OIDC service principal lacks `Storage Blob Data Contributor` on the state storage account.
Verify with:

```bash
az role assignment list \
  --scope "$(az storage account show -g rg-tfstate-prod -n tfstatestorage --query id -o tsv)" \
  --query "[?roleDefinitionName=='Storage Blob Data Contributor']"
```

### OIDC Token Exchange Failure

If `ARM_USE_OIDC=true` but authentication fails, check that:

1. The federated credential subject matches the GitHub Actions workflow trigger
   (`repo:<ORG>/<REPO>:ref:refs/heads/main` for push to main)
2. The `id-token: write` permission is set on the workflow job
3. The `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` secrets are correct

### Fallback: Access Key Authentication (Not Recommended for Production)

```bash
az storage account keys list -g rg-tfstate-prod -n tfstatestorage --query "[0].value" -o tsv
```

```hcl
# In backend.hcl — only for emergency/local debugging
use_oidc   = false
access_key = "<key>"
```
