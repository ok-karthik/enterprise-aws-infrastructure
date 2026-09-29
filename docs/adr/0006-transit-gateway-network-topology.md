# ADR 0006: Transit Gateway vs VPC Peering vs Cloud WAN

- Status: accepted
- Date: 2026-09-29

## Context

As the platform scales across multiple AWS accounts (`network-hub`, `shared-services`, `workloads-dev`, `workloads-prod`, `security-tooling`) and multiple regions (`eu-central-1`, `eu-west-1`), a robust network topology is required to interconnect VPCs, on-premises networks, and inspection hubs.

Three primary AWS networking constructs exist: Full-mesh VPC Peering, AWS Transit Gateway (TGW), and AWS Cloud WAN.

## Decision

Implement a **regional AWS Transit Gateway (TGW)** in the `network-hub` account (`iac-modules-repo/network/transit-gateway`), shared with member accounts via AWS Resource Access Manager (RAM).

1. **Segmented Route Tables**: Dedicated TGW route tables for:
   - `prod` (production workload spokes)
   - `nonprod` (dev/staging workload spokes)
   - `shared` (shared services, central endpoints)
   - `inspection` (central egress and Network Firewall)
2. **Deterministic Route Isolation**: Production spokes never associate or propagate into non-production route tables.
3. **Spoke Attachments**: Managed via `iac-modules-repo/network/tgw-attachment` with explicit association.

## What I chose against and what it cost

- **Full-Mesh VPC Peering**:
  - *Why rejected*: Peering complexity scales as $O(N^2)$. Connecting 15 VPCs requires 105 individual peering connections and hundreds of static route table entries. VPC peering does not support transitive routing, making central traffic inspection and central egress impossible.
- **AWS Cloud WAN**:
  - *Why rejected*: Cloud WAN is designed for global multi-region enterprise networks with dozens of international regions. For a primary European footprint (Frankfurt and Dublin), Cloud WAN introduces unnecessary core-network policy overhead and high fixed hourly costs without architectural benefit.
- **Cost of Transit Gateway**:
  - *Financial cost*: ~$36/month per VPC attachment plus $0.02 per GB processed. This cost is accepted to achieve network segmentation, central inspection, and scalable routing.

## Consequences

- Clean hub-and-spoke network topology with centralized route control.
- Production and non-production network traffic completely isolated at Layer 3.
- Foundation established for centralized egress inspection and DNS resolution.
