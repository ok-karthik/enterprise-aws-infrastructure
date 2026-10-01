# Workloads Live Stacks (`workloads-live-repo`)

Declarative Terragrunt live configuration for platform stacks deployed in workload accounts (`workloads-dev` in NonProd, `workloads-prod` in Prod).

## Status Legend

| Status | Meaning |
|---|---|
| ✅ **applied** | Applied to AWS; proof linked. |
| 📝 **plan-only** | Syntactically valid, linted, tested offline; not applied (pending account creation or cost considerations). |
| 📐 **design-only** | Architectural blueprint tested offline; not wired into a live stack. |

---

## Live Stack Catalog & Status

| Account | Region | Stacks Included | Status | Cost / Operational Notes |
|---|---|---|---|---|
| `workloads-dev` | `eu-central-1` | `vpc`, `eks`, `discovery-publisher`, `account-baseline`, `budgets`, `break-glass-alerts` | 📝 plan-only | Non-production dev environment; spot instances enabled, single NAT gateway for cost optimization |
| `workloads-prod` | `eu-central-1` (Primary) | `vpc`, `eks`, `discovery-publisher`, `account-baseline`, `budgets`, `break-glass-alerts` | 📝 plan-only | Production primary region; multi-AZ NAT, hardened EKS with private API endpoint, discovery published to SSM |
| `workloads-prod` | `eu-west-1` (DR Standby) | `vpc`, `eks` | 📝 plan-only | **Cost barrier**: Warm standby DR environment with zero-sized node groups; kept plan-only to avoid duplicate NAT gateway and VPC costs |
