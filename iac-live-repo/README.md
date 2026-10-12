# Live Stacks (`iac-live-repo`)

Declarative Terragrunt live configuration for every AWS account of the platform: the landing zone (management, security, network, observability) and the workload accounts (`workloads-dev` in NonProd, `workloads-prod` in Prod).

## How it is laid out

```
iac-live-repo/
  root.hcl                  # the only root: provider, backend, tags, and the only file that looks anything up
  _config/                  # the account registry (accounts.hcl), regions.hcl, organization.hcl
  _bootstrap/               # Day-0 CloudFormation stack and bootstrap.sh
  <account>/<region or _global>/<stack>/terragrunt.hcl
```

- The folder path is the configuration: `<account>` must be a key in `_config/accounts.hcl`, `<region>` is an AWS region, and `_global` means "account-wide, run from the primary region".
- Each `terragrunt.hcl` is the whole stack: module source, dependencies and every input. It includes `root.hcl` and nothing else. `scripts/check-account-registry.sh` fails if a stack uses `read_terragrunt_config`, `get_env(` or another `find_in_parent_folders`.
- A stack reads account and region values as `include.root.locals.<name>` (`account_name`, `account_id`, `env`, `ou`, `alias`, `owner`, `data_classification`, `aws_region`, plus `registry`, `regions`, `organization`).
- Module sources are always the local `iac-modules-repo/` checkout.
- `_config/accounts.local.hcl` (gitignored) holds the real account ids and emails; CI reads the same text from the `ACCOUNTS_LOCAL_HCL` repository variable.

## Status Legend

| Status | Meaning |
|---|---|
| ✅ **applied** | Applied to AWS; proof linked. |
| 📝 **plan-only** | Syntactically valid, linted, tested offline; not applied (pending account creation, sandbox setup or cost considerations). |
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
| `network-hub` | `eu-central-1` | `transit-gateway`, `tgw-peering` (requester), `dns` | 📝 plan-only | Regional Transit Gateway hub with prod/nonprod/inspection route domains |
| `network-hub` | `eu-central-1` | `inspection-egress` | 📝 plan-only | **Cost barrier**: AWS Network Firewall (~$220/endpoint/month + NAT gateway hourly costs) |
| `network-hub` | `eu-west-1` (DR) | `transit-gateway`, `tgw-peering` (accepter), `dns`, `inspection-egress` | 📝 plan-only | **Cost barrier**: DR secondary standby infrastructure duplicate hourly charges + Network Firewall |
| `shared-services` | `eu-central-1` | `central-endpoints` | 📝 plan-only | Central VPC Interface Endpoints and Private Hosted Zones |
| `observability` | `eu-central-1` | `oam`, `guardrail-signals` | 📝 plan-only | Central CloudWatch OAM monitoring sink and security alarm rules |
| `workloads-dev` | `eu-central-1` | `vpc`, `eks`, `discovery-publisher`, `account-baseline`, `budgets`, `break-glass-alerts`, `cost-janitor` | 📝 plan-only | Non-production dev environment; single NAT gateway for cost optimization; `cost-janitor` is report-only |
| `workloads-prod` | `eu-central-1` (Primary) | `vpc`, `eks`, `discovery-publisher`, `account-baseline`, `budgets`, `break-glass-alerts` | 📝 plan-only | Production primary region; hardened EKS with private API endpoint, discovery published to SSM |
| `workloads-prod` | `eu-west-1` (DR Standby) | `vpc`, `eks` | 📝 plan-only | **Cost barrier**: Warm standby DR environment with zero-sized node groups; kept plan-only to avoid duplicate NAT gateway and VPC costs |
