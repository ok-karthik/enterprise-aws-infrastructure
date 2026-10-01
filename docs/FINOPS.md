# 💰 FinOps & Cost Optimization Strategy

> **Status:** Design, not measured yet. Cost models and savings projections are architectural estimates; real numbers require a production payer account and historical billing data.

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

## 📈 What the landing zone itself costs (PLAN 9.2)

**Not measured yet.** Nothing in the new organization has been applied, so there is no bill to read. The estimates below are written from memory of AWS list prices and behaviour, **not checked against current pricing pages**: verify each before quoting it. This section
says what will cost money, and how to measure it once it does. Fill the "measured" column from real data (after one
full month) and delete this paragraph.

| Item | Cost driver | Estimate | Measured |
|---|---|---|---|
| Per-account baseline (`account-baseline`, KMS keys, IAM, SSM parameters) | 2 customer-managed KMS keys per account and region (about $1/month each) plus API calls | a few dollars per account | not yet |
| Config, GuardDuty, Security Hub (per account) | Billed per recorded configuration item, per event and per check. **The biggest baseline line in most landing zones.** | tens of dollars per account, grows with resources | not yet |
| Organization CloudTrail | The first management-event trail is free; data events, CloudTrail Lake and the log storage are not | depends on data events | not yet |
| NAT per VPC vs central egress | See the egress section above | about $105 per spoke VPC (3 AZs) vs a shared firewall | not yet |
| Cross-account observability (`observability/oam`) | Links are free. Cross-account metrics, logs and traces are shared without extra charge; you pay for what is stored and queried in each account | none extra | not yet |
| Managed Prometheus (optional flag) | Per ingested sample and per stored sample | zero until `enable_prometheus = true` | n/a |
| Cost Anomaly Detection, CUR 2.0 export | Anomaly Detection is free; the export costs S3 storage and any Athena queries | cents to a few dollars | not yet |
| Guardrail alarms (`observability/guardrail-signals`) | Six alarms and six metric filters | about $0.60/month | not yet |

**How to measure it** (after a month of real use):

1. In Cost Explorer, group by **Service** and filter on the platform accounts (log-archive, security-tooling, network-hub,
   shared-services, observability, management). That is the cost of the foundation.
2. Group by **Linked account** for the per-account baseline, on a workload account that has no workloads yet.
3. For "NAT per VPC vs central egress", compare `NatGateway-Hours` and `NatGateway-Bytes` usage types per account against the
   inspection VPC's, using the CUR query in `iac-modules-repo/governance/billing/README.md`.
4. Use Infracost on a plan for a module to see its estimate before it is applied (CI already does this per PR).

## 🏷️ Cost Allocation
Every resource is tagged with `Project`, `Environment`, `Owner` and `DataClassification` (from `default_tags`). For a per-team **showback** the `CostCenter` tag must also be *activated* for cost allocation, which `governance/billing` does through `cost_allocation_tags` once a resource with that tag has appeared in billing data. See the Athena query in that module's README.

## 🛡️ Shield Advanced (PLAN 6.4)

> ⚠️ **AWS Shield Advanced costs $3,000/month per AWS Organization** (not per account).
> The subscription auto-renews annually and covers all accounts in the organization once
> enabled from any single account.

| Item | Approximate monthly cost |
|---|---|
| Subscription (org-wide) | $3,000 flat |
| Data Transfer Out (DDoS protection) | $0.050/GB (first 100 TB) |
| Application Layer DDoS Mitigation | Included in subscription |

**When to enable:** only when the business case justifies the $36,000/year base cost —
typically when potential DDoS impact exceeds that amount (customer-facing SaaS, financial
services, regulated industries). The `security/shield-advanced` module is **disabled by
default** (`enabled = false`); the prod leaf can opt in.

**What you get:** automatic layer-3/4 DDoS mitigation, application-layer DDoS
auto-remediation (WAF rate-based rules created by Shield), proactive engagement with the
AWS Shield Response Team (SRT), cost protection (credits for scaling costs caused by
DDoS), and advanced metrics/reporting.

## 🔥 Firewall Manager (PLAN 6.1)

| Item | Approximate monthly cost |
|---|---|
| FMS WAFv2 policy (per region, per account) | $100 per policy + web ACL charges |
| WAFv2 web ACL (per ACL) | $5/month |
| WAFv2 rule (per rule) | $1/month |
| WAFv2 request pricing | $0.60 per million requests |
| Bot Control (if enabled) | $10/month + $1 per million requests |
| SG audit policy | $100 per policy per region |

Start in **audit mode** (`remediation_enabled = false`) and review findings before
enabling auto-remediation.

## 🌍 Multi-region DR (PLAN 7)

Warm standby costs money even when nothing has failed. Prices are list prices from memory; **check them with
Infracost or the AWS pricing calculator before applying** and put the real numbers here.

| Item | Why it costs | Notes |
|---|---|---|
| Aurora Global Database secondary | A full second cluster (at least one `db.r*` instance) plus cross-region replication traffic | Usually the biggest DR line. `data/postgres` (single RDS) is far cheaper but has no second region |
| EKS in `eu-west-1` | Control plane is billed per hour even with zero nodes (about $0.10/h per cluster) | The node group is at 0; NAT and endpoints in that VPC add up if enabled |
| S3 replication | Storage in both regions + per-request + inter-region transfer | Off unless `replication_destination_bucket_arn` is set |
| AWS Backup copies | Recovery-point storage in a second region + transfer | Shorten `copy_retention_days` for non-prod |
| Route 53 health checks | Small per-check monthly fee | Cheap. 10-second interval costs more than 30-second |
| Route 53 ARC | Per cluster, per hour (a few thousand dollars a year) | Not in the modules. Only worth it for prod where a false failover is expensive |
| State bucket replication | Negligible (state files are tiny) | |

**Rule of thumb:** DR roughly doubles the cost of the data tier and adds a fixed cost for the second cluster. Turn
it on for prod only, and write the number next to the RTO you bought with it.

## 🚀 Future Roadmap
- **Automated "Shutdown at Night"**: Implementation of instance scheduling for `dev` environments.
- **Karpenter Integration**: Replacing Cluster Autoscaler with Karpenter for more aggressive rightsizing of Kubernetes nodes.
