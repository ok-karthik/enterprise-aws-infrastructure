# ADR 0007: Central Egress + Network Firewall vs NAT per Spoke VPC

- Status: draft
- Date: 2026-09-29

## Context

Production and non-production workloads on EKS and EC2 need outbound internet connectivity to fetch container base images, pull package dependencies, and communicate with external SaaS APIs. Traditional AWS architectures deploy dedicated NAT Gateways in each VPC's public subnets.

Regulatory standards (SOC 2 CC6.6, ISO 27001 A.8.20, NIS2) require inspecting outbound traffic and blocking unauthorized data exfiltration. Furthermore, deploying multi-AZ NAT Gateways across dozens of workload accounts incurs massive fixed costs.

## Decision

Deploy a **Central Egress VPC** in the `network-hub` account (`iac-modules-repo/network/inspection-egress`) utilizing **AWS Network Firewall** placed behind a single shared pool of multi-AZ NAT Gateways.

1. **Routing**: Spoke VPCs configure `egress_mode = "central"` in `iac-modules-repo/network/vpc`, which routes `0.0.0.0/0` over Transit Gateway to the inspection VPC rather than creating local NAT gateways.
2. **Stateful Inspection**: AWS Network Firewall enforces domain allow-lists in `STRICT_ORDER` with drop-by-default behavior.
3. **Local NAT Flexibility**: Dev and sandbox accounts retain the option for `egress_mode = "local-nat"` with a single NAT gateway to keep development self-contained.

## What I chose against and what it cost

- **Dedicated NAT Gateways per Spoke VPC**:
  - *Why rejected*: A multi-AZ VPC (3 AZs) requires 3 NAT Gateways at ~$35/month each (~$105/month per account). Across 10 accounts, NAT Gateways alone cost ~$1,050/month with zero traffic inspection or egress domain filtering.
  - *FinOps Comparison*: Centralizing egress reduces total NAT gateways to 3 in the hub account, saving ~$945/month across 10 accounts. This cost savings offsets the base AWS Network Firewall fee (~$290/month per endpoint) while introducing stateful domain filtering and centralized VPC flow logging.
- **Third-Party Virtual Appliances (Palo Alto / Fortinet)**:
  - *Why rejected*: High licensing costs, complex high-availability failover scripts, and maintenance burden. AWS Network Firewall is fully managed with cloud-native CloudWatch metric integration.

## Consequences

- Full egress traffic visibility and domain allow-listing across all production workloads.
- Substantial FinOps savings as the number of AWS accounts grows.
- Compliance with German and EU cybersecurity directives (NIS2, DORA) regarding ICT outbound traffic monitoring.
