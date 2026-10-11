# Migration: two live repos to one `iac-live-repo` (2026-10)

> The previous step, one account to a multi-account organization, is in `2026-single-to-multi-account.md` (historical).

## What changed

- `foundation-live-repo/` and `workloads-live-repo/` are merged into one live repo, `iac-live-repo/`, with one `root.hcl`, one `_config/` registry and one `_bootstrap/`. The helper scripts moved to the repo-root `scripts/`.
- The folder path is the configuration: `iac-live-repo/<account>/<region or _global>/<stack>/terragrunt.hcl`. Account comes from path segment 0, the region from segment 1 (`_global` means the primary region).
- Every stack is one `terragrunt.hcl` (module source, dependencies, all inputs) that includes only `root.hcl`. `_envcommon/`, `account.hcl`, `env.hcl` and `region.hcl` are gone; the registry gained `alias`, `owner` and `data_classification` per account.
- Module sources are always the local `iac-modules-repo` folder: `module_versions`, `IAC_MODULES_LOCAL` and Renovate's module-pin rules are gone. Release tags stay, for outside consumers.
- The state key is now the path relative to `iac-live-repo/root.hcl` (`<account>/<region>/<stack>`). Only the five applied stacks need a state move (below); the `Service` tag changes in place.

## Old to new paths (all 46 stacks)

| Old leaf folder | New leaf folder |
|---|---|
| `foundation-live-repo/infrastructure/network-hub/_global/network/ipam` | `iac-live-repo/network-hub/_global/ipam` |
| `foundation-live-repo/infrastructure/network-hub/eu-central-1/network/dns` | `iac-live-repo/network-hub/eu-central-1/dns` |
| `foundation-live-repo/infrastructure/network-hub/eu-central-1/network/inspection-egress` | `iac-live-repo/network-hub/eu-central-1/inspection-egress` |
| `foundation-live-repo/infrastructure/network-hub/eu-central-1/network/tgw-peering` | `iac-live-repo/network-hub/eu-central-1/tgw-peering` |
| `foundation-live-repo/infrastructure/network-hub/eu-central-1/network/transit-gateway` | `iac-live-repo/network-hub/eu-central-1/transit-gateway` |
| `foundation-live-repo/infrastructure/network-hub/eu-west-1/network/dns` | `iac-live-repo/network-hub/eu-west-1/dns` |
| `foundation-live-repo/infrastructure/network-hub/eu-west-1/network/inspection-egress` | `iac-live-repo/network-hub/eu-west-1/inspection-egress` |
| `foundation-live-repo/infrastructure/network-hub/eu-west-1/network/tgw-peering` | `iac-live-repo/network-hub/eu-west-1/tgw-peering` |
| `foundation-live-repo/infrastructure/network-hub/eu-west-1/network/transit-gateway` | `iac-live-repo/network-hub/eu-west-1/transit-gateway` |
| `foundation-live-repo/infrastructure/observability/eu-central-1/observability/guardrail-signals` | `iac-live-repo/observability/eu-central-1/guardrail-signals` |
| `foundation-live-repo/infrastructure/observability/eu-central-1/observability/oam` | `iac-live-repo/observability/eu-central-1/oam` |
| `foundation-live-repo/infrastructure/shared-services/eu-central-1/network/central-endpoints` | `iac-live-repo/shared-services/eu-central-1/central-endpoints` |
| `foundation-live-repo/management/_global/governance/account-factory` | `iac-live-repo/management/_global/account-factory` |
| `foundation-live-repo/management/_global/governance/bootstrap-stacksets` | `iac-live-repo/management/_global/bootstrap-stacksets` |
| `foundation-live-repo/management/_global/governance/data-perimeter` | `iac-live-repo/management/_global/data-perimeter` |
| `foundation-live-repo/management/_global/governance/organization` | `iac-live-repo/management/_global/organization` |
| `foundation-live-repo/management/eu-central-1/governance/account-baseline` | `iac-live-repo/management/eu-central-1/account-baseline` |
| `foundation-live-repo/management/eu-central-1/governance/billing` | `iac-live-repo/management/eu-central-1/billing` |
| `foundation-live-repo/management/eu-central-1/governance/budgets` | `iac-live-repo/management/eu-central-1/budgets` |
| `foundation-live-repo/management/eu-central-1/identity/identity-center` | `iac-live-repo/management/eu-central-1/identity-center` |
| `foundation-live-repo/management/eu-central-1/observability/guardrail-signals` | `iac-live-repo/management/eu-central-1/guardrail-signals` |
| `foundation-live-repo/management/eu-central-1/security/break-glass-alerts` | `iac-live-repo/management/eu-central-1/break-glass-alerts` |
| `foundation-live-repo/management/eu-central-1/security/org-cloudtrail` | `iac-live-repo/management/eu-central-1/org-cloudtrail` |
| `foundation-live-repo/management/eu-central-1/security/security-alerts` | `iac-live-repo/management/eu-central-1/security-alerts` |
| `foundation-live-repo/security/log-archive/eu-central-1/security/log-archive` | `iac-live-repo/log-archive/eu-central-1/log-archive` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/access-analyzer` | `iac-live-repo/security-tooling/eu-central-1/access-analyzer` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/auto-remediation` | `iac-live-repo/security-tooling/eu-central-1/auto-remediation` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/firewall-manager` | `iac-live-repo/security-tooling/eu-central-1/firewall-manager` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/org-config` | `iac-live-repo/security-tooling/eu-central-1/org-config` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/security-alerts` | `iac-live-repo/security-tooling/eu-central-1/security-alerts` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/threat-detection` | `iac-live-repo/security-tooling/eu-central-1/threat-detection` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/compute/eks` | `iac-live-repo/workloads-dev/eu-central-1/eks` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/account-baseline` | `iac-live-repo/workloads-dev/eu-central-1/account-baseline` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/budgets` | `iac-live-repo/workloads-dev/eu-central-1/budgets` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/cost-janitor` | `iac-live-repo/workloads-dev/eu-central-1/cost-janitor` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/discovery-publisher` | `iac-live-repo/workloads-dev/eu-central-1/discovery-publisher` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/network/vpc` | `iac-live-repo/workloads-dev/eu-central-1/vpc` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/security/break-glass-alerts` | `iac-live-repo/workloads-dev/eu-central-1/break-glass-alerts` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/compute/eks` | `iac-live-repo/workloads-prod/eu-central-1/eks` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/governance/account-baseline` | `iac-live-repo/workloads-prod/eu-central-1/account-baseline` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/governance/budgets` | `iac-live-repo/workloads-prod/eu-central-1/budgets` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/governance/discovery-publisher` | `iac-live-repo/workloads-prod/eu-central-1/discovery-publisher` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/network/vpc` | `iac-live-repo/workloads-prod/eu-central-1/vpc` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/security/break-glass-alerts` | `iac-live-repo/workloads-prod/eu-central-1/break-glass-alerts` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-west-1/compute/eks` | `iac-live-repo/workloads-prod/eu-west-1/eks` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-west-1/network/vpc` | `iac-live-repo/workloads-prod/eu-west-1/vpc` |

## Owner: state move (Karthik, by hand, after merging; the implementer never does this)

**The new keys are the same as in the two-repo version of this plan.** The state key is the path relative to `iac-live-repo/root.hcl`,
so `management/_global/organization` and so on. Only the five already-applied stacks need a move. Everything else has never been applied
and simply starts at its new key.

**Move them, don't recreate them:**
- `organization`: an organization with member accounts can't be deleted and recreated.
- `account-factory`: a destroy tries to close the member accounts. Closures are rate-limited and closed accounts sit suspended for 90 days.
- `bootstrap-stacksets`: a destroy deletes the CI roles and state buckets in the member accounts.
- `budgets` / `identity-center` *could* be recreated, but moving is simpler and keeps the access assignments stable.

```bash
export AWS_PROFILE=ok.karthik9_tf_admin TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache
B=s3://tg-state-954171757349-eu-central-1
mv_state() { aws s3 cp "$B/$1/terraform.tfstate" "$B/$2/terraform.tfstate"; }
mv_state management/_global/governance/organization        management/_global/organization
mv_state management/_global/governance/account-factory     management/_global/account-factory
mv_state management/_global/governance/bootstrap-stacksets management/_global/bootstrap-stacksets
mv_state management/eu-central-1/identity/identity-center  management/eu-central-1/identity-center
mv_state management/eu-central-1/governance/budgets        management/eu-central-1/budgets

for s in _global/organization _global/account-factory _global/bootstrap-stacksets eu-central-1/identity-center eu-central-1/budgets; do
  (cd iac-live-repo/management/$s && terragrunt plan -out=tfplan)
done
```
**Each plan must show** `0 to add, N to change, 0 to destroy`, and every change must be `tags`/`tags_all`, with `Service` going from the
old path (`management/_global/governance/organization`) to the new one (`management/_global/organization`). **Anything else** (a create, a
destroy, a changed argument): stop, don't apply, keep the old keys. The copy is non-destructive.

If all five are clean: `terragrunt apply tfplan` in each folder. Then remove the old keys (the bucket is versioned, so they stay recoverable):
`aws s3 rm "$B/management/_global/governance/organization/terraform.tfstate"` and the other four. `aws s3 ls $B --recursive` should then
list exactly the five new keys.
