1: # Identity & Assignment Design
2:
3: This document defines the canonical identity model for the platform so customer access, FSLogix requirements, and AVD assignments are predictable and automatable.
4:
5: Key statements
6: - All customer users and platform/service principals exist in the same Microsoft Entra (Azure AD) tenant. We do not rely on separate customer tenants for identity isolation.
7: - All customer assignments (access to AVD workspaces, application groups and FSLogix shares) are driven by Azure/Entra security groups. Group-based assignments are the canonical mapping for Terraform and onboarding manifests.
8: - Entra Domain Services (AADDS) is deployed in the platform (identity subscription) to satisfy SMB/NTLM/Kerberos requirements for FSLogix profile shares and legacy domain-joined scenarios.
9:
10: Group-based assignment patterns
11: - Naming: adopt a machine-parsable naming scheme: `cust-<customer>-<purpose>-<env>` (examples: `cust-acme-avd-ws`, `cust-acme-apps-office365`, `cust-acme-fslogix`). Include a short description with customer id and intended scope.
12: - One group per customer per assignment type: create separate groups for workspace membership, application group membership, and FSLogix storage access. This allows least-privilege and clear audit trails.
13: - Terraform mapping: onboarding manifests create groups (or reference existing groups) and feed group object IDs into module inputs: `modules/avd` consumes `workspace_group_id` and `application_group_ids`; `modules/storage`/`modules/fslogix` consumes `fslogix_group_id` for SMB ACLs.
14:
15: AVD assignment examples
16: - Workspace assignment (shared model): assign a customer workspace group to the shared workspace resource. This grants the group's members access to the workspace and implicitly the app-groups assigned to that workspace.
17: - Application group assignment: map per-customer application groups to application groups within the hostpool. Use `application_group_ids` input as a list so multiple groups can be assigned.
18: - FSLogix storage access: use AADDS-backed SMB with NTFS/SMB ACLs applied to the storage share for the `cust-<customer>-fslogix` group. The Terraform module configures the storage account, private endpoint, and NTFS/SMB ACLs via AADDS identities.
19:
20: Platform vs Landing Zone vs Customer RBAC boundaries
21: - Platform RBAC (global): platform operators manage `bootstrap/`, `networking/hub-and-spoke/`, `modules/aadds` and other global services in the platform subscription(s). Assignments here are limited to platform service principals and operations groups.
22: - Landing zone RBAC (shared/dedicated roots): landing zone owners (platform team or separate landing zone operators) manage `environments/shared/` and `environments/dedicated/`. They have Contributor-level rights to deploy host pools, storage, and networking in their subscription(s).
23: - Customer RBAC (granular): customer administrators (mapped to Entra groups) are granted access to customer-specific resource groups (dedicated subscription or per-customer resource group in shared model) with limited roles (Reader, Storage File Data SMB Share Elevated Contributor as needed). Use `modules/customer` to assign these roles consistently.
24:
25: Identity dependencies between shared and dedicated models
26: - Shared model: single host pool/workspace is used for many customers. Identity-wise, all customers exist in the same tenant and are separated by group memberships. FSLogix profile storage is implemented as per-customer storage accounts (or containers) and access is enforced via AADDS-backed SMB ACLs using the customer group identity.
27: - Dedicated model: dedicated host pools and storage are deployed in a customer subscription but still rely on the platform AADDS instance for SMB/Kerberos. If network latency or isolation concerns require, a dedicated AADDS instance per customer (deployed in that customer's VNet) can be considered — document tradeoffs before adopting.
28: - Cross-model concerns: because both models use a single Entra tenant and a common AADDS (by default), ensure network peering and DNS allow AADDS resolvability from all spokes. If a customer requires full identity isolation, the dedicated pattern must be used with separate tenant or a dedicated AADDS instance (out of scope for default platform offering).
29:
30: Operational notes & onboarding
31: - Onboarding manifests should include optional `group_id` references for existing customer groups or a `create_group` boolean to have Terraform create groups and their descriptions.
32: - The recommended onboarding flow: (1) create or reference groups, (2) supply group IDs to `environments/shared` or `environments/dedicated` inputs, (3) apply landing zone; modules wire assignments to workspaces, app groups, and storage ACLs.
33: - Document RBAC elevation procedures and role expiration policies in `docs/runbook-add-customer.md` (operational runbooks exist but update them with the group-based model where necessary).
34:
35: FSLogix and AADDS technical constraints
36: - FSLogix uses SMB file shares and requires domain authentication that supports Kerberos and NTLM. Pure Azure AD (cloud-only) accounts do not provide the required LDAP/NTLM/Kerberos semantics. Use AADDS (managed domain) or hybrid AD DS for SMB ACLs.
37: - AADDS aircrafts a managed domain but has constraints: password hash sync, managed service identity limits, and may require reboots for domain join automation. Validate performance and join timing in pre-production.
38:
39: Tradeoffs
40: - Single-tenant Entra simplifies user administration and SSO but increases blast radius; dedicated tenants provide strong isolation but increase operational overhead and are not the default pattern for the platform.
41: - Central AADDS reduces management but introduces a dependency and potential single point of failure for FSLogix; consider geo-redundant AADDS or per-region instances for customers with strict SLAs.
42:
43: References
44: - docs/reference-architecture.md
45: - docs/runbook-add-customer.md
46:
