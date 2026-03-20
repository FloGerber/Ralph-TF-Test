# Azure Virtual Desktop Platform — OpenTofu IaC

This repository contains the full Infrastructure-as-Code (IaC) for a multi-tenant Azure Virtual
Desktop (AVD) platform built with [OpenTofu](https://opentofu.org). It implements a hub-and-spoke
architecture delivering both **shared RemoteApp** environments (multiple customers on a pooled
session host fleet) and **dedicated Personal Desktop** environments (isolated per customer).

---

## Architecture Overview

```
                        ┌─────────────────────────────┐
                        │    Hub VNet (10.0.0.0/16)   │
                        │  Azure Firewall Premium      │
                        │  AADDS (avdshared.local)     │
                        │  Private DNS Zones           │
                        │  GatewaySubnet / Mgmt nets   │
                        └──────────┬──────────┬────────┘
                                   │  Peering │  Peering
               ┌───────────────────┘          └──────────────────────┐
               │                                                      │
  ┌────────────▼────────────┐                       ┌────────────────▼────────────┐
  │  Shared Spoke           │                       │  Dedicated Spoke            │
  │  (10.1.0.0/16)          │                       │  (10.2.0.0/16)              │
  │                         │                       │                             │
  │  Pooled Host Pool       │                       │  Personal Host Pool         │
  │  RemoteApp only         │                       │  Full Desktop               │
  │  Multi-customer         │                       │  Per-customer isolation     │
  │                         │                       │                             │
  │  FSLogix Premium Files  │                       │  FSLogix Premium Files      │
  │  per customer           │                       │  per customer               │
  └─────────────────────────┘                       └─────────────────────────────┘
```

### Hub-and-Spoke Topology

| VNet | Address Space | Key Subnets | Purpose |
|------|--------------|-------------|---------|
| Hub (`vnet-hub-prod`) | `10.0.0.0/16` | GatewaySubnet, AzureFirewallSubnet, snet-aadds, snet-management | Centralized connectivity, security, AADDS |
| Shared Spoke (`vnet-shared-prod`) | `10.1.0.0/16` | snet-shared-app, snet-shared-avd, snet-shared-storage | Shared multi-tenant AVD workloads |
| Dedicated Spoke (`vnet-dedicated-prod`) | `10.2.0.0/16` | snet-dedicated-app, snet-dedicated-avd, snet-dedicated-storage | Isolated per-customer AVD desktops |

All inter-spoke traffic is inspected by the Azure Firewall Premium in the hub. AADDS domain
controllers are in the hub and accessed from both spokes. DNS servers on spoke VNets point to
AADDS domain controller IPs (injected on a second apply pass after AADDS deploys).

---

## Repository Layout

```
.
├── bootstrap/                  # One-time platform foundation (state backend, hub VNet, firewall)
├── networking/
│   └── hub-and-spoke/          # Standalone hub-and-spoke networking root module
├── imaging/
│   └── image-builder/          # Azure Image Builder golden image pipeline
├── environments/
│   ├── shared/                 # Shared multi-tenant AVD environment (Layer 2)
│   └── dedicated/              # Per-customer dedicated AVD environment (Layer 3)
├── modules/
│   ├── aadds/                  # Azure AD Domain Services
│   ├── avd/                    # AVD control plane + Flexible VMSS session hosts
│   ├── customer/               # Customer resource groups + RBAC
│   ├── dedicated/              # Composite per-customer AVD wrapper
│   ├── fslogix/                # FSLogix profile container storage
│   ├── monitoring/             # Log Analytics + alerts
│   ├── networking/             # VNet / subnet / NSG / firewall / peering
│   └── storage/                # Storage accounts, file shares, private endpoints
├── BACKEND.md                  # OIDC setup, backend configuration, SP roles
├── WORKSPACES.md               # Workspace and deployment guide
├── CHECKOV.md                  # Checkov IaC security scanning guide
├── AVM.md                      # Azure Verified Modules evaluation notes
└── docs/
    ├── architecture-decisions.md     # Architecture decision records
    ├── runbook-add-customer.md       # Runbook: onboard a new customer
    └── runbook-image-update.md       # Runbook: update golden image
```

---

## Module Map

| Module | Purpose | Key Resources |
|--------|---------|--------------|
| `modules/aadds` | Azure AD Domain Services | `azurerm_active_directory_domain_service`, conditional RG, GPO config tracking via `null_resource` |
| `modules/avd` | AVD core: host pool, app groups, workspaces, Flexible VMSS session hosts | `azurerm_virtual_desktop_host_pool`, `azurerm_orchestrated_virtual_machine_scale_set`, diagnostic settings |
| `modules/customer` | Per-customer onboarding and RBAC | Resource groups, `Desktop Virtualization User`, `Storage File Data SMB Share Contributor` assignments |
| `modules/dedicated` | Composite per-customer AVD environment | Wraps `networking` + `storage` + `avd`; optional hub peering and UDR |
| `modules/fslogix` | FSLogix profile container storage | Premium FileStorage, file shares, private endpoints, network rules |
| `modules/monitoring` | Observability | Log Analytics Workspace, action groups, metric alerts, diagnostic settings |
| `modules/networking` | VNet / subnets / NSGs / firewall / peering | VNet, subnets, NSG, optional Azure Firewall, optional VNet peering |
| `modules/storage` | Azure Storage for AVD profiles and app attach | `azurerm_storage_account`, file shares, private endpoints, RBAC |

---

## Deployment Order

> **Important:** Each layer is an independent OpenTofu root configuration with its own remote
> backend. Do NOT call environment directories as child modules — they contain `terraform {}`
> blocks with `backend {}` configurations. Deploy each layer separately.

```
Step 1  bootstrap/               → Creates state backend (run once)
Step 2  networking/hub-and-spoke/ → Hub-and-spoke networking foundation
Step 3  imaging/image-builder/   → Golden image build pipeline (optional, can run anytime)
Step 4  environments/shared/     → Shared multi-tenant AVD environment
                                    (includes AADDS — requires 2-pass apply; see WORKSPACES.md)
Step 5  environments/dedicated/  → Per-customer dedicated AVD environments
```

See [WORKSPACES.md](WORKSPACES.md) for full step-by-step deployment commands and state key details.

---

## Key Design Decisions

- **Shared pool: RemoteApp only** — The shared host pool uses `preferred_app_group_type = "RailApplications"`. Customers receive published applications, not full desktops. This maximises session density.
- **Flexible VMSS for session hosts** — Session hosts use `azurerm_orchestrated_virtual_machine_scale_set` (Flexible Orchestration mode) for Gen2 + Trusted Launch compatibility and Availability Zone spreading.
- **AADDS in the hub VNet** — Azure AD Domain Services is deployed in the hub so both shared and dedicated spokes can domain-join without separate domain controllers.
- **Two-pass AADDS deployment** — AADDS domain controller IPs are only known after AADDS is provisioned. Apply the networking layer once with empty DNS servers, then re-apply after AADDS to inject the IPs.
- **FSLogix via Azure Premium Files** — Each customer gets a dedicated Premium FileStorage account (ZRS) with SMB private endpoints. Profiles are delivered over the private endpoint, never over the public internet.
- **Checkov dual integration** — IaC security scanning runs both as a pre-commit hook and as a GitHub Actions CI step. See [CHECKOV.md](CHECKOV.md) for suppression policy and the full suppressed-checks register.

See [docs/architecture-decisions.md](docs/architecture-decisions.md) for full decision records.

---

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.6
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.55
- An Azure subscription with `Owner` or `Contributor` + `User Access Administrator`
- A service principal with OIDC federated credentials configured (see [BACKEND.md](BACKEND.md))
- [tflint](https://github.com/terraform-linters/tflint) (for local linting)
- [checkov](https://www.checkov.io/) >= 3.2 (for local security scanning)
- [pre-commit](https://pre-commit.com/) (optional, recommended)

### Install pre-commit hooks

```bash
pip install pre-commit checkov
pre-commit install
```

---

## Quick Start

```bash
# 1. Clone and enter the repo
git clone <repo-url>
cd Ralph-TF-Test

# 2. Bootstrap state backend (run once)
cd bootstrap
tofu init
tofu apply -var="oidc_sp_app_id=<app-id>" -var="oidc_sp_object_id=<object-id>"
cd ..

# 3. Deploy hub-and-spoke networking
cd networking/hub-and-spoke
tofu init -backend-config=../../backend.hcl
tofu apply
cd ../..

# 4. Deploy shared environment
cd environments/shared
tofu init -backend-config=../../backend.hcl
tofu apply     # First pass: deploys AADDS; note domain_controller_ips from output
# Update aadds_dns_server_ips in locals.tf or via -var, then:
tofu apply     # Second pass: injects AADDS DNS IPs into spoke VNet
cd ../..
```

See [WORKSPACES.md](WORKSPACES.md) for complete instructions including the dedicated environment
and image builder pipeline.

---

## Security Posture

| Control | Implementation |
|---------|---------------|
| No public endpoints | All storage accounts have `public_network_access_enabled = false`; access is via private endpoints only |
| Network isolation | Hub firewall inspects all inter-spoke traffic; NSGs restrict inbound by subnet |
| Premium firewall | Azure Firewall Premium with IDS mode `Deny` and Threat Intelligence mode `Deny` |
| Identity | OIDC federated credentials for CI/CD (no long-lived client secrets); managed identities for all Azure resources |
| Encryption | TLS 1.2 minimum on all storage; encryption at rest enabled by default |
| IaC scanning | Checkov scans every pull request; 0 unsuppressed critical/high findings required |
| Image hardening | Golden images built by Azure Image Builder include security baselines (Credential Guard, DEP, UAC, Windows Firewall) |
