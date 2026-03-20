# Hub-and-Spoke Networking — Standalone Platform Layer

This directory is a **standalone deployable root module** (not a child module). It manages all
hub and static spoke VNets for the platform networking layer, including peerings, NSGs,
Azure Firewall, and Private DNS Zones linked to the hub VNet.

> **Deploy order**: `bootstrap/` → `networking/hub-and-spoke/` → `environments/shared/` → `environments/dedicated/`

## Quick Start

```bash
# From this directory
tofu init -backend-config=backend.hcl
tofu plan
tofu apply
```

The `backend.hcl` points at the shared Azure Blob Storage state container with key
`networking/hub-and-spoke`. Populate the storage account name and resource group from
`bootstrap/` outputs before running `init`.

## Outputs

| Output | Description |
|--------|-------------|
| `hub_vnet_id` | Resource ID of the hub VNet |
| `shared_spoke_vnet_id` | Resource ID of the shared spoke VNet |
| `dedicated_spoke_vnet_id` | Resource ID of the dedicated spoke VNet |
| `hub_firewall_private_ip` | Private IP address of the Azure Firewall |
| `subnet_ids` | Map of subnet logical names → subnet IDs |
| `private_dns_zone_ids` | Map of DNS zone names → resource IDs |

Downstream modules (e.g. `environments/shared/`) should consume these outputs via
`terraform_remote_state` or by passing them as variables.

## Network Topology Overview

### Architecture Components

The landing zone implements a three-tier hub-and-spoke network architecture:

```
┌──────────────────────────────────────────────────────────────┐
│                        HUB VNET (10.0.0.0/16)                │
│                                                              │
│  ┌────────────────────┐  ┌─────────────┐  ┌──────────────┐ │
│  │ Gateway Subnet     │  │ Firewall    │  │ Management   │ │
│  │ (10.0.0.0/27)      │  │ (10.0.1.0/24│  │ (10.0.2.0/24)│ │
│  │ - ExpressRoute     │  │ - Core      │  │ - Bastion    │ │
│  │   Gateway          │  │   security  │  │ - Jumpbox    │ │
│  └────────────────────┘  │   services  │  └──────────────┘ │
│                          └─────────────┘                    │
│  ┌────────────────────┐  ┌─────────────────────────────┐   │
│  │ Frontend Subnet    │  │ Backend Subnet              │   │
│  │ (10.0.3.0/24)      │  │ (10.0.4.0/24)               │   │
│  │ - Load Balancers   │  │ - Shared Services           │   │
│  │ - WAF              │  │ - API Management            │   │
│  └────────────────────┘  └─────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
          ▲ Peering              ▲ Peering
          │                      │
   ┌──────┴──────┐        ┌──────┴──────┐
   │             │        │             │
┌──┴─────────────┴──┐ ┌──┴─────────────┴──┐
│ SHARED SPOKE      │ │ DEDICATED SPOKE   │
│ (10.1.0.0/16)     │ │ (10.2.0.0/16)     │
│                   │ │                   │
│ ┌───────────────┐ │ │ ┌───────────────┐ │
│ │ App Subnet    │ │ │ │ App Subnet    │ │
│ │ (10.1.0.0/24) │ │ │ │ (10.2.0.0/24) │ │
│ │ - Shared apps │ │ │ │ - Customer 1  │ │
│ └───────────────┘ │ │ └───────────────┘ │
│                   │ │                   │
│ ┌───────────────┐ │ │ ┌───────────────┐ │
│ │ AVD Subnet    │ │ │ │ AVD Subnet    │ │
│ │ (10.1.1.0/24) │ │ │ │ (10.2.1.0/24) │ │
│ │ - Shared AVD  │ │ │ │ - Customer 1  │ │
│ └───────────────┘ │ │ └───────────────┘ │
└───────────────────┘ └───────────────────┘
```

## Network Isolation Boundaries

### Hub VNet (10.0.0.0/16)
- **Purpose**: Centralized hub for shared services and network ingress/egress
- **Subnets**:
  - **GatewaySubnet** (10.0.0.0/27): ExpressRoute Gateway for hybrid connectivity
  - **AzureFirewallSubnet** (10.0.1.0/24): Azure Firewall for centralized security
  - **Management** (10.0.2.0/24): Bastion, Jump hosts, and management services
  - **Frontend** (10.0.3.0/24): Load balancers, WAF, and public-facing services
  - **Backend** (10.0.4.0/24): Shared backend services (API Management, databases, etc.)

### Shared Spoke VNet (10.1.0.0/16)
- **Purpose**: Shared Application Landing Zone for common enterprise services
- **Subnets**:
  - **App** (10.1.0.0/24): Shared application workloads
  - **AVD** (10.1.1.0/24): Azure Virtual Desktop session hosts

### Dedicated Spoke VNet (10.2.0.0/16)
- **Purpose**: Customer-specific or dedicated workload isolation
- **Subnets**:
  - **App** (10.2.0.0/24): Dedicated customer applications
  - **AVD** (10.2.1.0/24): Dedicated customer AVD infrastructure

## Network Peering Configuration

The hub-and-spoke topology uses virtual network peering to enable communication:

### Peering Relationships
1. **Hub ↔ Shared Spoke**: Bidirectional peering with forwarded traffic enabled
   - Allows hub services to reach shared spoke resources
   - Enables spoke-to-spoke communication through hub

2. **Hub ↔ Dedicated Spoke**: Bidirectional peering with forwarded traffic enabled
   - Provides spoke access to shared hub services
   - Isolates dedicated spoke workloads from other spokes

### Peering Configuration
- **Allow Virtual Network Access**: Enabled (allows peered VNets to communicate)
- **Allow Forwarded Traffic**: Enabled (allows traffic not originating in peered VNet)
- **Gateway Transit**: Enabled on hub peering (allows spokes to use hub's ExpressRoute gateway)

## Network Security Groups (NSGs)

### Hub NSG Rules
Security rules protecting the hub network:
- **Inbound**:
  - Allow Azure Load Balancer health probes to management subnet (RDP)
  - Allow internet HTTPS to frontend subnet (443)
  - Allow all VNet-to-VNet traffic
  - Deny all other inbound traffic (default deny)
- **Outbound**:
  - Allow all outbound to internet
  - Allow all VNet-to-VNet traffic

### Shared Spoke NSG Rules
Security rules protecting the shared spoke:
- **Inbound**:
  - Allow RDP from hub management subnet (3389)
  - Allow HTTPS from hub frontend subnet (443)
  - Allow all VNet-to-VNet traffic
  - Deny all other inbound traffic (default deny)
- **Outbound**:
  - Allow all outbound to internet
  - Allow all outbound to Azure Firewall

### Dedicated Spoke NSG Rules
Security rules protecting the dedicated spoke:
- **Inbound**:
  - Allow RDP from hub management subnet (3389)
  - Allow HTTPS from hub frontend subnet (443)
  - Allow all VNet-to-VNet traffic
  - Deny all other inbound traffic (default deny)
- **Outbound**:
  - Allow all outbound to internet
  - Allow all outbound to Azure Firewall

## Core Services in Hub

### Azure Firewall
- **Location**: AzureFirewallSubnet (10.0.1.0/24)
- **SKU**: AZFW_VNet with Standard tier
- **Firewall Policy**: 
  - Threat Intelligence Mode: Deny (blocks traffic to known malicious IPs/domains)
  - IDPS Mode: Deny (intrusion detection prevention system)
- **Security Posture**: Enterprise-grade traffic filtering and monitoring

### ExpressRoute Gateway (Planned)
- **Location**: GatewaySubnet (10.0.0.0/27)
- **Purpose**: Hybrid connectivity to on-premises networks
- **Configuration**: Supports both ExpressRoute and Site-to-Site VPN

### Bastion Host (Planned)
- **Location**: Management subnet (10.0.2.0/24)
- **Purpose**: Secure RDP/SSH access to VMs without public IPs

### NAT Gateway (Future)
- **Purpose**: Centralized outbound connectivity for spoke workloads

## Routing Architecture

### User-Defined Routes (UDRs)
The network implements forced tunneling through the Azure Firewall:
- Spoke subnets route all non-local traffic through the firewall
- The firewall performs centralized threat intelligence filtering
- This ensures all egress traffic is inspected and logged

### Effective Routes
- **Hub VNet**: Direct routing within hub; peered spoke routes via peering
- **Spoke VNets**: Default routes to firewall for inspection; peering routes to hub

## Workload Isolation Strategy

### Isolation Levels
1. **Network Level**: Separate VNets prevent layer-3 cross-workload traffic
2. **Subnet Level**: NSGs enforce strict inbound/outbound rules per subnet
3. **Application Level**: Application-level firewalling via Azure Firewall policies

### Cross-Spoke Communication
- **Shared Spoke ↔ Dedicated Spoke**: Must route through hub firewall
- **Control**: Firewall policies determine what traffic is allowed
- **Audit**: All cross-spoke traffic is logged and can be monitored

## Connectivity Scenarios

### Scenario 1: On-Premises to Azure
- ExpressRoute circuit → Hub gateway
- Routes through hub firewall for inspection
- Reaches any spoke via peering

### Scenario 2: Internet to Azure
- Internet traffic → Load Balancer in hub frontend subnet
- Firewall inspects inbound traffic
- Reaches backend services or spoke resources

### Scenario 3: Spoke to On-Premises
- Workload in spoke initiates outbound connection
- Traffic forced through hub firewall via UDR
- ExpressRoute gateway routes to on-premises
- Return traffic flows through same path

### Scenario 4: Spoke-to-Spoke Communication
- Shared spoke to dedicated spoke requires firewall approval
- Peering enables direct communication path
- NSG rules at both spoke ingress points
- Firewall policies control allowed traffic types

## Deployment Variables

Key variables that can be customized:

| Variable | Default | Description |
|----------|---------|-------------|
| `location` | eastus | Azure region for all resources |
| `environment` | prod | Environment name (dev, prod, etc.) |
| `resource_group_name` | rg-avd-networking | Resource group name |
| `hub_vnet_address_space` | ["10.0.0.0/16"] | Hub VNet CIDR block |
| `shared_spoke_vnet_address_space` | ["10.1.0.0/16"] | Shared spoke CIDR block |
| `dedicated_spoke_vnet_address_space` | ["10.2.0.0/16"] | Dedicated spoke CIDR block |
| `tags` | Environment, Project, ManagedBy | Resource tags |

## Security Best Practices Implemented

1. **Defense in Depth**
   - NSGs at subnet level
   - Azure Firewall at hub level
   - Threat intelligence enabled
   - IDPS (Intrusion Detection Prevention) enabled

2. **Least Privilege Access**
   - Explicit allow rules for required traffic
   - Default deny for all other traffic
   - RDP only from management subnet
   - HTTPS only from frontend subnet

3. **Centralized Security**
   - All traffic through single firewall (choke point)
   - Centralized logging and monitoring
   - Consistent security policies across all workloads

4. **Network Segmentation**
   - Separate VNets prevent blast radius
   - NSGs enforce boundaries between subnets
   - Spoke isolation from each other

## Monitoring and Logging

### Resources to Enable
- **Network Watcher**: Flow logs for NSG traffic analysis
- **Firewall Logs**: Monitor threat intel hits and IDPS events
- **Application Gateway**: WAF logs for web traffic analysis
- **Log Analytics**: Centralized log aggregation and analysis

### Key Metrics to Monitor
- Blocked inbound connections (NSG)
- Threat intelligence hits (Firewall)
- IDPS detections (Firewall)
- Cross-spoke traffic volume
- Egress traffic patterns

## Scaling and Future Enhancements

### Adding New Spoke VNets
1. Create new spoke VNet with unique address space
2. Create subnets with appropriate prefixes
3. Create NSG with security rules for isolation
4. Establish peering to hub VNet (both directions)
5. Update firewall rules to permit/deny cross-spoke traffic

### Multi-Region Deployment
- Deploy hub-and-spoke per region
- Use VNet peering or private endpoints for inter-region communication
- Firewall policies replicated across regions

### ExpressRoute Integration
- Configure gateway in GatewaySubnet
- Connect to ExpressRoute circuit
- Enable gateway transit on peering relationships
- On-premises systems can reach all spokes

## Terraform Files

- **main.tf**: Core resource definitions (VNets, subnets, NSGs, peering, firewall)
- **variables.tf**: Input variables with defaults
- **outputs.tf**: Output values for VNet IDs and configuration details

## Quality Assurance

All configurations pass:
- ✅ `tofu fmt -check` - Consistent formatting
- ✅ `tofu validate` - Terraform syntax validation
- ✅ `checkov -f main.tf --framework terraform` - Security best practices

## References

- [Azure Landing Zone Documentation](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/)
- [Hub-Spoke Network Topology](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
- [Azure Firewall Best Practices](https://learn.microsoft.com/en-us/azure/firewall/best-practices)
- [NSG Best Practices](https://learn.microsoft.com/en-us/azure/virtual-network/security-best-practices)
