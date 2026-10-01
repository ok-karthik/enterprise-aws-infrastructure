# Infrastructure Modules (`iac-modules-repo`)

Reusable, versioned Terraform modules published and consumed across platform landing zone stacks and developer tenant capabilities.

## Status Legend

Every module in this repository is honestly labeled with its operational status:

| Status | Meaning |
|---|---|
| ✅ **applied** | Applied to a real AWS sandbox or production account at least once; verification proof linked. |
| 📝 **plan-only** | Syntactically valid, linted, tested offline, and wired into an active Terragrunt live stack; not applied to AWS (typically due to infrastructure running costs or pending account creation). |
| 📐 **design-only** | Validated and tested offline with mock providers (`terraform test`); not currently wired into an active live stack in this repository. May be consumed externally by `internal-developer-platform` (IDP). |

---

## Module Catalog

| Category | Module | Status | Consumed By | Description & Guardrails |
|---|---|---|---|---|
| `compute` | [`eks`](compute/eks/) | 📝 plan-only | `workloads-live-repo` | Hardened EKS cluster, IMDSv2 hop-limit 1, private endpoint, KMS secrets encryption |
| `data` | [`aurora-postgres`](data/aurora-postgres/) | 📐 design-only | — | Aurora PostgreSQL Global Database with cross-region replication and storage encryption |
| `data` | [`backup`](data/backup/) | 📐 design-only | — | Centralized AWS Backup vaults with cross-region copy rules and retention lifecycle policies |
| `data` | [`postgres`](data/postgres/) | 📐 design-only | `internal-developer-platform` | Tenant RDS PostgreSQL capability with KMS encryption and Secrets Manager rotation |
| `edge` | [`cloudfront`](edge/cloudfront/) | 📐 design-only | — | Secure CloudFront CDN distribution with TLS 1.2+ enforce and origin access controls |
| `governance` | [`account-baseline`](governance/account-baseline/) | 📝 plan-only | `foundation-live-repo`, `workloads-live-repo` | Account baselining: permissions boundaries, EBS/S3 encryption defaults, regional KMS CMKs |
| `governance` | [`account-factory`](governance/account-factory/) | 📝 plan-only | `foundation-live-repo` | Declarative AWS Organizations account vending driven by `_config/accounts.hcl` |
| `governance` | [`billing`](governance/billing/) | 📝 plan-only | `foundation-live-repo` | AWS CUR 2.0 Data Export configuration, Athena query scaffolding, and Cost Anomaly monitors |
| `governance` | [`bootstrap-stacksets`](governance/bootstrap-stacksets/) | 📝 plan-only | `foundation-live-repo` | CloudFormation StackSets vending Day-0 bootstrap state bucket, OIDC, and CI roles |
| `governance` | [`budgets`](governance/budgets/) | 📝 plan-only | `foundation-live-repo`, `workloads-live-repo` | Per-account monthly cost budgets with 50/80/100% threshold notifications and anomaly detection |
| `governance` | [`data-perimeter`](governance/data-perimeter/) | 📝 plan-only | `foundation-live-repo` | Resource Control Policies (RCPs) restricting S3, KMS, SQS, and Secrets Manager to the organization |
| `governance` | [`discovery-publisher`](governance/discovery-publisher/) | 📝 plan-only | `workloads-live-repo` | Publishes standard SSM Parameter Store discovery contract (`/platform/<env>/<region>/...`) |
| `governance` | [`organization`](governance/organization/) | 📝 plan-only | `foundation-live-repo` | AWS Organizations structure, OU hierarchy, and baseline Service Control Policies (SCPs) |
| `identity` | [`ack-cross-account`](identity/ack-cross-account/) | 📐 design-only | — | AWS Controllers for Kubernetes (ACK) hub-spoke cross-account IAM role and tenant boundary |
| `identity` | [`human-access`](identity/human-access/) | 📐 design-only | `internal-developer-platform` | EKS access entries and cluster view policies for human engineers |
| `identity` | [`identity-center`](identity/identity-center/) | 📝 plan-only | `foundation-live-repo` | IAM Identity Center permission sets, ABAC session tags, and group-to-account assignments |
| `identity` | [`workload-iam`](identity/workload-iam/) | 📐 design-only | `internal-developer-platform` | Documented interface stub for workload pod identity and IRSA role vending |
| `identity` | [`workload-identity`](identity/workload-identity/) | 📐 design-only | `internal-developer-platform` | EKS Pod Identity associations with IRSA federated OIDC fallback |
| `network` | [`central-endpoints`](network/central-endpoints/) | 📝 plan-only | `foundation-live-repo` | Shared VPC interface endpoints and private hosted zones in shared-services |
| `network` | [`dns`](network/dns/) | 📝 plan-only | `foundation-live-repo` | Route 53 Resolver endpoints, cross-account forwarding rules, and resolver query logs |
| `network` | [`inspection-egress`](network/inspection-egress/) | 📝 plan-only | `foundation-live-repo` | Central egress VPC + AWS Network Firewall stateful domain filtering (cost barrier) |
| `network` | [`ipam`](network/ipam/) | 📝 plan-only | `foundation-live-repo` | IP Address Manager (IPAM) pools for global, regional, and environment CIDR delegations |
| `network` | [`route53-failover`](network/route53-failover/) | 📐 design-only | — | Route 53 health-checked active-passive multi-region DNS failover routing |
| `network` | [`tgw-peering`](network/tgw-peering/) | 📝 plan-only | `foundation-live-repo` | Cross-region Transit Gateway peering (requester and accepter sides); no static routes over it yet |
| `network` | [`tgw-attachment`](network/tgw-attachment/) | 📐 design-only | — | Spoke VPC Transit Gateway attachment and route table association module |
| `network` | [`transit-gateway`](network/transit-gateway/) | 📝 plan-only | `foundation-live-repo` | Regional Transit Gateway hub with isolated prod/nonprod/shared/inspection route domains |
| `network` | [`vpc`](network/vpc/) | 📝 plan-only | `workloads-live-repo` | Multi-AZ VPC with flow logs, deny-all default NACLs, and IPAM/local-NAT options |
| `observability` | [`guardrail-signals`](observability/guardrail-signals/) | 📝 plan-only | `foundation-live-repo` | CloudTrail metric filters and alarms detecting unauthorized boundary or SCP modifications |
| `observability` | [`oam`](observability/oam/) | 📝 plan-only | `foundation-live-repo` | CloudWatch Observability Access Manager (OAM) central sinks and member account links |
| `security` | [`access-analyzer`](security/access-analyzer/) | 📝 plan-only | `foundation-live-repo` | Organization-wide IAM Access Analyzer for external and unused access findings |
| `security` | [`auto-remediation`](security/auto-remediation/) | 📝 plan-only | `foundation-live-repo` | EventBridge rule and Lambda function automatically revoking 0.0.0.0/0 SSH/RDP rules |
| `security` | [`break-glass-alerts`](security/break-glass-alerts/) | 📝 plan-only | `foundation-live-repo`, `workloads-live-repo` | EventBridge + SNS alerts notifying on any BreakGlassAdmin role assumption |
| `security` | [`firewall-manager`](security/firewall-manager/) | 📝 plan-only | `foundation-live-repo` | AWS Firewall Manager organization-wide WAF policies (cost barrier) |
| `security` | [`log-archive`](security/log-archive/) | 📝 plan-only | `foundation-live-repo` | Dedicated S3 Object Lock (COMPLIANCE) audit buckets for CloudTrail, Config, and flow logs |
| `security` | [`org-cloudtrail`](security/org-cloudtrail/) | 📝 plan-only | `foundation-live-repo` | Organization-wide multi-region CloudTrail delivering encrypted events to log-archive |
| `security` | [`org-config`](security/org-config/) | 📝 plan-only | `foundation-live-repo` | AWS Config organization-wide aggregator and foundational detective compliance rules |
| `security` | [`security-alerts`](security/security-alerts/) | 📝 plan-only | `foundation-live-repo` | EventBridge + SNS notification pipelines for high-severity GuardDuty and Security Hub findings |
| `security` | [`shield-advanced`](security/shield-advanced/) | 📐 design-only | — | AWS Shield Advanced DDoS protection configuration ($3,000/mo flat cost barrier) |
| `security` | [`threat-detection`](security/threat-detection/) | 📝 plan-only | `foundation-live-repo` | Central GuardDuty, Security Hub, Inspector v2, Macie (optional Audit Manager, default off) |
| `security` | [`waf-logging`](security/waf-logging/) | 📐 design-only | — | Kinesis Firehose / S3 WAF traffic logging stream configuration |
| `storage` | [`s3`](storage/s3/) | 📐 design-only | `internal-developer-platform` | Tenant S3 bucket capability with Block Public Access and SSE-AES256 enforcement |
