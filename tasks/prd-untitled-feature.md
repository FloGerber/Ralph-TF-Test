**File:** `tasks/prd-azure-virtual-desktop-multi-tenant-environment-with-opentofu-v3.md`

**10 User Stories (US-014 → US-023):**

| Story | Title | Tier |
|---|---|---|
| US-014 | Resolve open questions → Architecture Decision Records | 1 |
| US-015 | Azure Firewall DNS proxy + AADDS DNS in spoke VNets | 2 |
| US-016 | Dedicated App Attach Premium File Share + AVD config | 2 |
| US-017 | Wire monitoring module into shared + dedicated environments | 2 |
| US-018 | OpenTofu unit tests — `modules/networking` | 3 |
| US-019 | OpenTofu unit tests — `modules/avd` | 3 |
| US-020 | OpenTofu unit tests — `modules/storage` + `modules/dedicated` | 3 |
| US-021 | Evaluate 5 additional AVM modules → update `AVM.md` | 4 |
| US-022 | Harden registration token expiry (2h rolling, regenerated per run) | 1 |
| US-023 | Full codebase quality gate sweep — `tofu validate` clean in all 13 dirs | 1 |

**Key decisions resolved (5 open questions from v2):** DNS proxy enabled, AADDS Standard SKU, App Attach GA 2024 as default, change-based image trigger, 2h token rotation.

**Quality gates on every story:** `tofu fmt -check` + `tofu validate` + `tofu plan` + `checkov` (0 unsuppressed critical/high) + `tflint` (0 errors).