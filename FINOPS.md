# 💰 FinOps & Cost Optimization Strategy

This platform is designed with "Cost-Aware Infrastructure" principles, ensuring transparency and efficiency in cloud spending.

## 📊 Cost Visibility (Infracost)
Every Pull Request triggers an automated cost breakdown using **Infracost**.
- **Visual Gating**: Cost changes are posted as comments in the PR.
- **Threshold Alerts**: Any change increasing monthly costs by more than 20% requires explicit Senior Engineer review.

## 💸 Saving Strategies

### 1. Spot Instance Orchestration
In the `dev` environment, we leverage **AWS Spot Instances** for EKS Managed Node Groups.
- **Impact**: Up to 90% cost reduction compared to On-Demand.
- **Graceful Termination**: Handled via the AWS Node Termination Handler.

### 2. Environment Life-cycling
Non-production environments follow a surgical lifecycle:
- **Manual Teardown**: A dedicated workflow allows for destroying expensive resources (RDS, EKS) when they are not needed for testing.
- **Resource Sizing**: `dev` environments use the smallest viable Nitro instances (e.g., `t3.medium`) compared to high-availability `prod` types.

### 3. Storage Optimization
- **S3 Intelligent-Tiering**: Automatically enabled for data buckets with unknown access patterns.
- **EBS Lifecycle**: Snapshots older than 30 days are automatically transitioned to Glacier or deleted (except for `prod`).

## 🌐 Egress: local NAT vs. central inspection (PLAN 5.3)

`network/vpc`'s `egress_mode` picks between two ways a spoke VPC reaches the internet:

| | `egress_mode = "local-nat"` (default) | `egress_mode = "central"` |
|---|---|---|
| NAT gateways | One per AZ, in every spoke VPC | None in the spoke; shared ones in `network/inspection-egress` (network-hub), one per AZ |
| Domain allow-list / firewalling | None | One AWS Network Firewall, shared by every spoke that opts in |
| Approximate monthly cost | ~$35 + data, **per spoke VPC** (3 AZs ≈ $105/month per VPC) | ~$35 + data per AZ **once**, in network-hub, **plus** Network Firewall: roughly $395/month per AZ endpoint + $0.065/GB processed (`us-east-1` pricing at the time this was written; check current pricing) |
| Extra hop | None | Spoke → transit gateway → inspection VPC → NAT → internet (added latency, and the transit gateway attachment cost, ~$36/month per attachment + data) |

**The crossover:** central egress is cheaper once enough spoke VPCs share the same firewall that their combined local-NAT cost would exceed the firewall's flat cost — roughly break-even around 8–12 always-on spoke VPCs at 3 AZs each, before counting the value of one enforced domain allow-list (which local NAT cannot give you at any spoke count). For a handful of workload accounts, `local-nat` is cheaper; it is also the default, so nothing changes until a spoke opts into `central` deliberately.

## 🏷️ Cost Allocation
100% of resources are tagged with `Project` and `Environment`. This allows for granular reporting in **AWS Cost Explorer** using Tag-Based Cost Allocation.

## 🚀 Future Roadmap
- **Automated "Shutdown at Night"**: Implementation of instance scheduling for `dev` environments.
- **Karpenter Integration**: Replacing Cluster Autoscaler with Karpenter for more aggressive rightsizing of Kubernetes nodes.
