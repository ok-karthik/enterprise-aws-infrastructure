# Foundation Live Stacks (`foundation-live-repo`)

Declarative Terragrunt live configuration for the platform landing zone: AWS Organizations management, shared security services, central networking hub, and platform observability.

## Status Legend

| Status | Meaning |
|---|---|
| ✅ **applied** | Applied to AWS; proof linked. |
| 📝 **plan-only** | Syntactically valid, linted, tested offline; not applied (pending sandbox setup or cost considerations). |
| 📐 **design-only** | Architectural blueprint tested offline; not wired into a live stack. |

---

## Live Stack Catalog & Status

| Account | Region / Scope | Stacks Included | Status | Cost / Operational Notes |
|---|---|---|---|---|
| `management` | `_global` | `organization`, `data-perimeter`, `account-factory`, `bootstrap-stacksets` | 📝 plan-only | Landing zone root; SCPs and RCPs target Policy-Staging OU initially |
| `management` | `eu-central-1` | `account-baseline`, `billing`, `budgets`, `identity-center`, `org-cloudtrail`, `security-alerts`, `break-glass-alerts`, `guardrail-signals` | 📝 plan-only | Org CloudTrail delivers to log-archive; Identity Center manages human access |
| `log-archive` | `eu-central-1` | `log-archive` | 📝 plan-only | S3 Object Lock compliance audit bucket for org-wide log ingestion |
| `security-tooling` | `eu-central-1` | `threat-detection`, `security-alerts`, `access-analyzer`, `auto-remediation`, `org-config` | 📝 plan-only | Delegated admin for GuardDuty, Security Hub, Inspector, Macie (Audit Manager default off) |
| `security-tooling` | `eu-central-1` | `firewall-manager` | 📝 plan-only | **Cost barrier**: AWS Firewall Manager ($100/policy/region) + AWS WAF rule group costs |
| `network-hub` | `_global` | `ipam` | 📝 plan-only | Org-wide IPAM pools for top-level and regional CIDR allocations |
| `network-hub` | `eu-central-1` | `transit-gateway`, `dns` | 📝 plan-only | Regional Transit Gateway hub with prod/nonprod/inspection route domains |
| `network-hub` | `eu-central-1` | `inspection-egress` | 📝 plan-only | **Cost barrier**: AWS Network Firewall (~$220/endpoint/month + NAT gateway hourly costs) |
| `network-hub` | `eu-west-1` (DR) | `transit-gateway`, `dns`, `inspection-egress` | 📝 plan-only | **Cost barrier**: DR secondary standby infrastructure duplicate hourly charges + Network Firewall |
| `shared-services` | `eu-central-1` | `central-endpoints` | 📝 plan-only | Central VPC Interface Endpoints and Private Hosted Zones |
| `observability` | `eu-central-1` | `oam`, `guardrail-signals` | 📝 plan-only | Central CloudWatch OAM monitoring sink and security alarm rules |
