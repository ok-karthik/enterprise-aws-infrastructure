# Plan: one live repo, simple Terragrunt, one file per stack

- **Written:** 2026-10-11 by Claude Opus 5.5 (planner). Revised the same day for **layout B** (one live repo). **Executor:** the `implementer` agent (Sonnet tier).
- **Branch:** `refactor/simple-terragrunt` from `main`. PR #71 (PLAN 9.5) is merged, including its review fixes.
- **One commit per part**, messages as given. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Do NOT:** push, open a PR, merge, use AWS credentials or the shell's default AWS profile, run `apply`/`destroy`/`import`/`state`/`force-unlock`,
  run `--backend-bootstrap`, or touch S3 state. The state move and the edits to guarded files are the **owner's** (sections "Owner: before" and "Owner: state move").
- Always `export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache` first (mobile data: never re-download the AWS provider).

## Goal

Today, to understand one stack you open the leaf, `root.hcl`, an `_envcommon` file, `env.hcl`, `account.hcl`, `region.hcl` and the registry
(287 lookups), spread over two live repos. That hid a real bug in PR #71 (dev EKS `min_size` set in two files). After this task:

- **One live repo:** `iac-live-repo/`, replacing `foundation-live-repo/` and `workloads-live-repo/`.
- **The folder path is the config:** `iac-live-repo/<account>/<region or _global>/<stack>/terragrunt.hcl`. Every top-level folder in
  `iac-live-repo/` that doesn't start with `_` is a registry account.
- **Each `terragrunt.hcl` is the whole stack:** module source, dependencies, every input. The only thing it includes is `iac-live-repo/root.hcl` (one copy).
- **`root.hcl` is the only file that looks anything up:** account from the path, everything else from the registry in `iac-live-repo/_config/`.
- **Scripts live in repo-root `scripts/`.**

Terragrunt keeps doing what it's good at: generating provider and backend, state key from the path, `dependency` with mock outputs, and `run --all`.
Isolation between accounts doesn't come from separate repos. It comes from per-account CI roles, per-account state buckets, GitHub
Environments and CODEOWNERS per account folder.

## Target tree

```
iac-live-repo/
  root.hcl                 # the only root (one copy)
  README.md                # merged from the two old live-repo READMEs
  _config/                 # moved from foundation-live-repo/_config (accounts.hcl, regions.hcl, organization.hcl, accounts.local.hcl.example)
  _bootstrap/              # moved from foundation-live-repo/_bootstrap
  management/_global/organization/terragrunt.hcl
  management/eu-central-1/budgets/terragrunt.hcl
  ...
  workloads-dev/eu-central-1/eks/terragrunt.hcl
scripts/                   # moved from workloads-live-repo/scripts (incl. tests/)
```

## Scope (only these may change)

| Part | Files |
|---|---|
| 1 | `foundation-live-repo/_config/accounts.hcl`, `foundation-live-repo/_config/accounts.local.hcl.example` |
| 2 | `foundation-live-repo/**` and `workloads-live-repo/**` except `workloads-live-repo/scripts/` → all become `iac-live-repo/**` (move, rewrite, delete); `.gitignore` line 19; `.github/CODEOWNERS` |
| 3 | `workloads-live-repo/scripts/**` → `scripts/**`; `iac-live-repo/_bootstrap/bootstrap.sh` |
| 4 | `.github/workflows/{terragrunt,reusable-terragrunt,drift-detection,destroy,finops-weekly}.yml`, `.github/actions/{setup-platform,static-analysis}/action.yml`, `.github/docker/Dockerfile` (comment line 7 only), `infracost-config.yml`, `renovate.json`, `.pre-commit-config.yaml`, `Makefile` |
| 5 | `iac-agents-repo/iac_agent/iac_agent.py`, `iac-agents-repo/catalog/**`, `iac-agents-repo/prompts/{iac_agent,architect,ci_healer}.md`, `iac-agents-repo/README.md`, `iac-agents-repo/tests/{test_platform,test_healer_guards}.py` |
| 6 | Docs (path and wording only): `AGENTS.md`, `README.md`, `docs/{ARCHITECTURE,CICD,COMPLIANCE,DISCOVERY_CONTRACT,FINOPS,IDENTITY,GOVERNANCE,DISASTER_RECOVERY}.md`, `docs/adr/{0001,0002,0003,0010,0012}-*.md`, `docs/runbooks/drill-bad-scp-rollback.md`, `docs/visualizer.html`, `docs/diagrams/{ci_cd_policy_gates,feedback_loops_quality_flywheel,multi_account_aws_infra}.html`, `.github/assets/visualizer.html`, `.github/CONTRIBUTING.md`, `iac-live-repo/README.md`, `iac-live-repo/_bootstrap/README.md`, `iac-modules-repo/README.md`, every `iac-modules-repo/*/*/README.md` that mentions a live-repo path, `iac-modules-repo/governance/bootstrap-stacksets/{main.tf,variables.tf}` (**the comment on line 2 of main.tf and the description string on line 2 of variables.tf only**), new `docs/migrations/2026-10-simple-layout.md`, and the first line only of `docs/migrations/2026-single-to-multi-account.md` |

**Never edit:** `.checkov.yaml`, `.claude/`, `policy-library-repo/` (owner, see "Owner: before" and "Owner follow-ups"), `.trivyignore`,
`PLAN.md`, `SIMPLIFY_PLAN.md`, `LEARNING_PLAN.md`, `learning/`, `docs/EXECUTION_LOG.md`, `**/CHANGELOG.md`, any other `iac-modules-repo/**/*.tf`.

## Owner: before the implementer starts (Karthik, by hand, ~5 minutes)

These files are human-only, and the move breaks them:

1. **`.claude/hooks/guard.py:312`** runs `REPO_ROOT / "workloads-live-repo" / "scripts" / "verify_module.py"`. After Part 3 that path is
   gone, so the post-edit hook and `make verify-module` break. Change it to work for both layouts during the migration:
   ```python
   verify = REPO_ROOT / "scripts" / "verify_module.py"
   if not verify.exists():
       verify = REPO_ROOT / "workloads-live-repo" / "scripts" / "verify_module.py"
   cmd = [sys.executable, str(verify), module]
   ```
   Then **`.claude/hooks/test_guard.py:117`** (`python3 workloads-live-repo/scripts/verify_module.py storage/s3`): change it to
   `python3 scripts/verify_module.py storage/s3` if that test checks the allow-list for the real path. Line 56 is only an example
   `apply` command string, so leave it. Run `python3 -m unittest discover -s .claude/hooks`.
2. **`.checkov.yaml` `directory:`** lists `foundation-live-repo` and `workloads-live-repo`. Replace those two lines with `  - iac-live-repo`
   (don't add `scripts`: it wasn't scanned before). **Do this after Part 2 lands**: Checkov fails on a missing directory. The implementer
   stops at the `make checkov` verify step if this isn't done yet.
3. **Local secrets file:** after Part 2, `mv foundation-live-repo/_config/accounts.local.hcl iac-live-repo/_config/` (gitignored, local only).
   The implementer needs it for the "after" render, so Part 2 step 6 does this move itself if the owner hasn't. It's a plain `mv` of a local file.
   The GitHub variable `ACCOUNTS_LOCAL_HCL` holds the file's *content*, not a path, so it doesn't change. Part 4 updates the path the setup action writes to.

## What was measured — do not re-derive (2026-10-11)

| # | Fact |
|---|---|
| M1 | 46 leaf `terragrunt.hcl` files (incl. the 9.5 `cost-janitor` leaf, now on `main`). 29 `_envcommon` files; `_envcommon/data/s3.hcl` has **0** users (it's the only `tfr://` source). |
| M2 | For every account, folder name == registry key == `account_name` in `account.hcl`. Account names are unique across both live repos, so the merged tree has **no collisions** (checked). Every region folder name == its `region.hcl` `aws_region`. Both `_global/region.hcl` say `eu-central-1` == `regions.hcl` `primary_region`. |
| M3 | Both old `root.hcl` copies are identical. Root uses the registry `id` first (`try(account_entry.id, account.hcl id)`), so dropping `account.hcl` doesn't change `account_id`. |
| M4 | `accounts.hcl`: `accounts = { for name, base in local.base_accounts : name => merge(base, try(local.local_accounts[name], {})) }`. `parse_registry()` in `generate_account_matrix.py` reads flat `key = "value"` lines per account. |
| M5 | Values leaves read today: `env_vars.module_versions` ×49, `region_vars.aws_region` ×23, `account_vars.account_name` ×14, `account_vars.env` ×10, `env_vars.env` ×9, `env_vars.cluster_name` ×8, `account_vars.aws_account_id` ×7, `env_vars.api_allowed_cidrs` ×4, `account_vars.{owner,ou,data_classification,account_alias}` ×4 each, `env_vars.{single_nat_gateway,min_size,enable_nat_gateway,desired_size}` ×2, `env_vars.scale_schedule` ×1. Plus 40 `read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/...")`. Some leaves read files by path, e.g. the bootstrap-stacksets leaf reads `foundation-live-repo/_bootstrap/cloudformation/*.yaml`: rewrite to `iac-live-repo/_bootstrap/...`. The **content** is the same, so its input is unchanged. |
| M6 | `terragrunt render --format json` works **offline for all 46 leaves** (exit 0; dependency outputs fall back to `mock_outputs`) with `env -u AWS_PROFILE AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null IAC_MODULES_LOCAL=1`. It needs the gitignored local `accounts.local.hcl`. Output has `.inputs`, `.terraform.source`, `.generate`, `.remote_state.config`, `.dependency`. |
| M7 | All workflows set `IAC_MODULES_LOCAL: '1'`, and the owner's applies used it too, so deployed code is always the local `iac-modules-repo`. Many release tags don't exist (billing, org-cloudtrail, guardrail-signals...). **Local source everywhere = no behaviour change.** |
| M8 | `_envcommon/governance/billing.hcl` has the only extra `generate` block (the `us_east_1` provider alias). |
| M9 | `renovate.json`: custom managers = Dockerfile ARGs (keep), `env.hcl` module pins (remove), `tfr://` (remove). 23 `packageRules`: 20 match an `env.hcl` (remove), 3 don't (keep). `release-please-config.json` has no live-repo paths. |
| M10 | **Scripts compute the repo root by depth.** At `workloads-live-repo/scripts/x.py` → `parents[2]`; at `scripts/x.py` it must be `parents[1]`. Affected: `check_policy_catalog.py:9`, `verify_module.py:39`, `generate_account_matrix.py:31` (`parents[2]` → `parents[1]`), and `check_discovery_contract.py:18` (`.parent.parent.parent` → `.parent.parent`). Tests use `parents[1]` relative to `tests/`, so they don't change depth. `verify_module.py:42` also hardcodes `REPO_ROOT / "workloads-live-repo" / "scripts" / "run-checkov.sh"`. Check every `.sh` for `dirname`/`..` depth too. |
| M11 | Every reference to the old repo names outside them (grep 2026-10-11): the files in the Scope table plus `.checkov.yaml`, `.claude/hooks/{guard.py:312,test_guard.py:56,117}`, `policy-library-repo/POLICIES.md:4`, `policy-library-repo/terraform/deny_member_org_admin.rego:6` (all owner). `.github/actions/static-analysis/action.yml` has 12 references (fmt, tflint `--chdir`, cfn-lint, unittest dirs, checkov/sarif/licenses scripts). `setup-platform/action.yml:32,46-48` writes `foundation-live-repo/_config/accounts.local.hcl`. `.gitignore:19` lists that file (line 20 `**/accounts.local.hcl` also covers it). `Makefile:4` `FMT_DIRS`, `:34,38,51,55`. `.pre-commit-config.yaml:16,23,31,43,45`. |
| M12 | Real fmt roots: `iac-modules-repo`, `foundation-live-repo`, `workloads-live-repo`, `policy-library-repo` (there is no `policies/`). After the move: `iac-modules-repo iac-live-repo policy-library-repo`. |
| M13 | Owner-applied stacks (bucket `tg-state-954171757349-eu-central-1`): `management/_global/governance/{organization,account-factory,bootstrap-stacksets}`, `management/eu-central-1/identity/identity-center`, `management/eu-central-1/governance/budgets`. |

## Decisions already made (don't reopen)

- **One live repo `iac-live-repo/`**, one `root.hcl`, one `_config/`, one `_bootstrap/`, scripts in repo-root `scripts/`. `foundation-live-repo/CODEOWNERS` and `workloads-live-repo/CODEOWNERS` are deleted; `.github/CODEOWNERS` owns `/iac-live-repo/`.
- **Account = path segment 0, region = segment 1 (`_global` → `primary_region`).** Delete every `account.hcl`, `env.hcl`, `region.hcl` and both `_envcommon/` folders.
- **The registry is the single source of truth.** It gains `alias`, `owner`, `data_classification` per account (copied from today's `account.hcl`).
- **Module source is always the local folder** (`${get_repo_root()}/iac-modules-repo/<category>/<module>`). `module_versions`, `IAC_MODULES_LOCAL` and Renovate's module-pin rules go. Release tags (release-please) stay, for outside consumers.
- **State key = `path_relative_to_include()`, i.e. the path relative to `iac-live-repo/root.hcl`:** `<account>/<region>/<stack>`.
  For the 5 applied stacks that's **exactly the same new key as in the two-repo version of this plan**, so the owner's 5 state moves are unchanged.
  The default tag `Service` is the same path and changes to it (in-place tag updates only).
- **The one-file rule becomes a test** (Part 3).

## Old → new paths (all 46; no collisions)

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

## The new `iac-live-repo/root.hcl` (write exactly this; it is the only root)

```hcl
# root.hcl: included by every stack (terragrunt.hcl) in iac-live-repo.
#
# The folder path IS the configuration:
#   <account>/<region or _global>/<stack>/terragrunt.hcl
#   - <account> must be a key in iac-live-repo/_config/accounts.hcl (the registry)
#   - <region> is an AWS region; _global means "account-wide", run from the primary region
#
# This is the ONLY file that looks anything up. A stack reads these values as include.root.locals.<name>.
locals {
  path_parts   = split("/", path_relative_to_include())
  account_name = local.path_parts[0]
  region_dir   = local.path_parts[1]

  registry     = read_terragrunt_config("${get_repo_root()}/iac-live-repo/_config/accounts.hcl").locals.accounts
  regions      = read_terragrunt_config("${get_repo_root()}/iac-live-repo/_config/regions.hcl").locals
  organization = read_terragrunt_config("${get_repo_root()}/iac-live-repo/_config/organization.hcl").locals

  # An unknown folder name fails here with "Invalid index": add the account to the registry first.
  account             = local.registry[local.account_name]
  account_id          = local.account.id
  env                 = local.account.env # dev | staging | prod | global
  ou                  = local.account.ou
  alias               = local.account.alias
  owner               = local.account.owner
  data_classification = local.account.data_classification
  aws_region          = local.region_dir == "_global" ? local.regions.primary_region : local.region_dir
}

# Wait up to 5 minutes for a state lock instead of failing at once (PLAN 8.3).
terraform {
  extra_arguments "lock_timeout" {
    commands  = ["plan", "apply", "destroy", "import", "refresh"]
    arguments = ["-lock-timeout=5m"]
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  # Fail closed: refuse to run against any account other than the one in the registry for this folder.
  allowed_account_ids = ["${local.account_id}"]

  default_tags {
    tags = {
      Environment        = "${title(local.env)}"
      ManagedBy          = "Terragrunt"
      Account            = "${local.account_name}"
      Project            = "enterprise-aws-platform"
      Service            = "${path_relative_to_include()}"
      Owner              = "${local.owner}"
      DataClassification = "${local.data_classification}"
    }
  }
}
EOF
}

# One state bucket per account and region (created by the Day-0 bootstrap, never by Terragrunt), one key per stack folder.
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "tg-state-${local.account_id}-${local.aws_region}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = "${local.aws_region}"
    encrypt      = true
    use_lockfile = true
  }
}
```

Before writing it, compare with today's `foundation-live-repo/root.hcl`. If today's file has any other block or setting not shown here, **keep it unchanged**
and say so in the report. (Measured: locals, `lock_timeout`, `generate "provider"`, `remote_state`; nothing else.)
Today's provider `contents` must stay byte-identical apart from the `Service` value and the comment line.

## The one-file leaf (template for all 46)

```hcl
# <One sentence: what this stack is, from the old _envcommon header comment.> Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/<category>/<module>"
}

# (only if the old leaf/_envcommon had one) copy every dependency block exactly, changing ONLY config_path:
dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = { ... }                                 # unchanged
  mock_outputs_allowed_terraform_commands = [ ... ]      # unchanged
}

# (only if needed) short names for values used several times:
locals {
  env = include.root.locals.env
}

inputs = {
  # every key the old merged inputs had, with the same value
}
```

How to fill a leaf, mechanically:
1. Take the **merged** inputs from the baseline render (`$BEFORE/<old>.json` → `.inputs`). That is the target: the new leaf's render must give the same JSON.
2. Write each input as the expression the old `_envcommon`/leaf used, translated with this table. If an input was a plain literal, or came from `env.hcl`, write the literal value.

   | Old expression | New expression |
   |---|---|
   | `local.account_vars.locals.account_name` | `include.root.locals.account_name` |
   | `local.account_vars.locals.env` / `local.env_vars.locals.env` | `include.root.locals.env` |
   | `local.account_vars.locals.aws_account_id` | `include.root.locals.account_id` |
   | `local.account_vars.locals.{ou,owner,data_classification}` | `include.root.locals.{ou,owner,data_classification}` |
   | `local.account_vars.locals.account_alias` | `include.root.locals.alias` |
   | `local.region_vars.locals.aws_region` | `include.root.locals.aws_region` |
   | `read_terragrunt_config(".../_config/accounts.hcl").locals.accounts` | `include.root.locals.registry` |
   | `read_terragrunt_config(".../_config/regions.hcl").locals` | `include.root.locals.regions` |
   | `read_terragrunt_config(".../_config/organization.hcl").locals` | `include.root.locals.organization` |
   | `local.env_vars.locals.<knob>` (cluster_name, min_size, desired_size, enable_nat_gateway, single_nat_gateway, api_allowed_cidrs, scale_schedule) | the literal value from that account's `env.hcl` |
   | `local.env_vars.locals.module_versions.*` / `local.module_source` | gone: `terraform.source` is the local path |
   | `dependency.x` with `config_path = "${get_terragrunt_dir()}/../../network/vpc"` | `config_path = "../vpc"` (sibling stack in the same account/region folder; use the mapping table) |
   | any other `${get_repo_root()}/foundation-live-repo/...` or `.../workloads-live-repo/...` file path (e.g. `_bootstrap/cloudformation/*.yaml`) | the same file under `${get_repo_root()}/iac-live-repo/...` |

3. Keep the "why" comments from `_envcommon` and the old leaf (attach them to the input they explain). Drop comments that only explain the old layering.
4. `billing`: copy `_envcommon/governance/billing.hcl`'s `generate` block into the billing leaf unchanged.
5. A dependency that points to a stack in **another** account or region: compute the relative path between the two **new** folders
   (e.g. `../../eu-west-1/tgw-peering`). Check it resolves: `ls <new leaf>/<config_path>/terragrunt.hcl`.
6. No `read_terragrunt_config`, no `find_in_parent_folders` (except in the `include "root"` block), no `get_env`.


## Part 0 — Preconditions and the baseline render on `main` (no commit)

```bash
export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache
cd /Users/karthik.orugonda/github/enterprise-aws-infrastructure
git status --short                                   # must be clean (stash or ask the owner if not); then:
git switch main && git pull --ff-only
git log --oneline main | grep -c "PLAN 9.5"           # >= 7, else STOP (PR #71 not on main)
test -d workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/cost-janitor || echo STOP   # the janitor leaf is part of main
test -f foundation-live-repo/_config/accounts.local.hcl || echo STOP          # render needs it (M6)
grep -n 'workloads-live-repo/scripts' .claude/hooks/guard.py                  # STOP if this still prints line 312 without the fallback ("Owner: before" step 1)
SNAP=/private/tmp/claude-501/simple-tg; rm -rf $SNAP; mkdir -p $SNAP/before $SNAP/after
awk -F'`' '/^\| `(foundation|workloads)-live-repo\//{print $2"\t"$4}' docs/plans/2026-10-11-simple-terragrunt.md > $SNAP/mapping.tsv; wc -l < $SNAP/mapping.tsv   # 46
render() {  # $1 = leaf dir, $2 = output file
  (cd "$1" && env -u AWS_PROFILE AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null IAC_MODULES_LOCAL=1 \
     timeout 120 terragrunt render --format json --non-interactive --log-format bare > "$2" 2>"$2.err")
}
while IFS=$'\t' read -r old new; do render "$old" "$SNAP/before/$(echo "$old" | tr / _).json" || echo "FAIL $old"; done < $SNAP/mapping.tsv
jq -c '.inputs | {min_size, scale_schedule}' $SNAP/before/workloads-live-repo_workloads_nonprod_workloads-dev_eu-central-1_compute_eks.json   # expect min_size 0
git switch -c refactor/simple-terragrunt
```
**STOP** and report if any check says STOP, any render fails, or dev EKS doesn't show `"min_size":0`. This plan file is untracked; it
stays where it is (don't commit it). The baseline must come from `main` **before** any change.

Save this as `$SNAP/compare.py` (scratch, not committed):

```python
"""Compare old vs new renders. Usage: python3 compare.py SNAP REPO_ROOT. Prints every difference; exit 1 if any."""
import json, os, re, sys
snap, repo = sys.argv[1], os.path.realpath(sys.argv[2])
pairs = [l.rstrip("\n").split("\t") for l in open(f"{snap}/mapping.tsv") if l.strip()]
old_to_new = {o: n for o, n in pairs}
def load(kind, path): return json.load(open(f"{snap}/{kind}/{path.replace('/', '_')}.json"))
def norm_provider(c): return [l for l in c.splitlines() if l.strip() and not l.strip().startswith("#") and not l.strip().startswith("Service")]
errors = 0
def bad(new, msg):
    global errors; errors += 1; print(f"DIFF {new}: {msg}")
for old, new in pairs:
    b, a = load("before", old), load("after", new)
    rel = new.split("/", 1)[1]          # path relative to iac-live-repo/root.hcl, e.g. management/_global/organization
    for k in sorted(set(b["inputs"]) | set(a["inputs"])):
        if b["inputs"].get(k) != a["inputs"].get(k): bad(new, f"input {k}: {b['inputs'].get(k)!r} -> {a['inputs'].get(k)!r}")
    if b["terraform"]["source"] != a["terraform"]["source"]: bad(new, f"source {b['terraform']['source']} -> {a['terraform']['source']}")
    if set(b["generate"]) != set(a["generate"]): bad(new, f"generate blocks {sorted(b['generate'])} -> {sorted(a['generate'])}")
    for g in b["generate"]:
        bc, ac = b["generate"][g]["contents"], a["generate"].get(g, {}).get("contents", "")
        if (norm_provider(bc) if g == "provider" else bc) != (norm_provider(ac) if g == "provider" else ac): bad(new, f"generate {g} contents differ")
    m = re.search(r'Service\s*=\s*"([^"]*)"', a["generate"]["provider"]["contents"])
    if not m or m.group(1) != rel: bad(new, f"Service tag {m and m.group(1)!r} != {rel!r}")
    rb, ra = b["remote_state"]["config"], a["remote_state"]["config"]
    for k in ("bucket", "region", "encrypt", "use_lockfile"):
        if rb.get(k) != ra.get(k): bad(new, f"remote_state {k}: {rb.get(k)} -> {ra.get(k)}")
    if ra.get("key") != rel + "/terraform.tfstate": bad(new, f"state key {ra.get('key')} != {rel}/terraform.tfstate")
    bdeps, adeps = b.get("dependency") or {}, a.get("dependency") or {}
    if set(bdeps) != set(adeps): bad(new, f"dependencies {sorted(bdeps)} -> {sorted(adeps)}")
    for d in set(bdeps) & set(adeps):
        bt = os.path.relpath(os.path.realpath(bdeps[d]["config_path"]), repo)
        at = os.path.relpath(os.path.realpath(adeps[d]["config_path"]), repo)
        if old_to_new.get(bt) != at: bad(new, f"dependency {d}: {bt} should map to {old_to_new.get(bt)}, got {at}")
        if bdeps[d].get("mock_outputs") != adeps[d].get("mock_outputs"): bad(new, f"dependency {d} mock_outputs differ")
print(f"{len(pairs)} stacks compared, {errors} differences"); sys.exit(1 if errors else 0)
```
Note: the "before" `config_path` points into the old folders, which are gone after Part 2. `realpath` still normalises the string
(it doesn't need the folder to exist), so the mapping lookup works. If a render JSON field name differs from what the script expects,
fix the script in scratch, never relax a check, and say so in the report.

## Part 1 — Registry gets alias, owner, data_classification

Commit: `refactor(config): registry carries alias, owner and data classification per account`

For every account in `base_accounts` in `foundation-live-repo/_config/accounts.hcl`, add three lines copied from that account's `account.hcl`:
`alias = "<account_alias>"`, `owner = "<owner>"`, `data_classification = "<data_classification>"`. Keep their `TODO(owner)` comments.
`terragrunt hcl fmt` it. Add the three fields to the header comment and to `accounts.local.hcl.example`'s comment (no values).
Nothing reads them yet: re-render 3 leaves and check their JSON is unchanged.

## Part 2 — Create `iac-live-repo/`

Commit: `refactor(live)!: one live repo, one terragrunt.hcl per stack, account and region from the path`

1. `mkdir iac-live-repo`; `git mv foundation-live-repo/_config iac-live-repo/_config`; `git mv foundation-live-repo/_bootstrap iac-live-repo/_bootstrap`;
   `git mv foundation-live-repo/root.hcl iac-live-repo/root.hcl`, then replace its content with the new root above.
2. For every row of the mapping table: `mkdir -p "$(dirname <new>)" && git mv <old> <new>` (keeps `.terraform.lock.hcl` and history).
3. Rewrite each moved `terragrunt.hcl` with the leaf template and the fill rules.
4. `iac-live-repo/README.md`: merge the two old live-repo READMEs into one (one status table: account | region | stacks | status | notes,
   with the new paths). `git rm` both old READMEs.
5. `git rm` every `account.hcl`, `env.hcl`, `region.hcl`, both `_envcommon/` folders, `workloads-live-repo/root.hcl`,
   `foundation-live-repo/CODEOWNERS`, `workloads-live-repo/CODEOWNERS`. After this, `foundation-live-repo/` must not exist, and
   `workloads-live-repo/` must contain only `scripts/` (moved in Part 3). Delete any `.terragrunt-cache`.
6. `.gitignore` line 19 → `iac-live-repo/_config/accounts.local.hcl`. Then make sure the local secrets file is at the new place:
   `ls iac-live-repo/_config/accounts.local.hcl || mv foundation-live-repo/_config/accounts.local.hcl iac-live-repo/_config/`
   (`git mv` of a folder usually carries untracked files along; this covers the case where it didn't). `git status` must not show it.
7. `.github/CODEOWNERS`: replace the `/foundation-live-repo/` and `/workloads-live-repo/` lines with:
   ```
   /iac-live-repo/            @ok-karthik
   # Per-account ownership, once there is more than one team (examples, keep commented):
   # /iac-live-repo/management/        @ok-karthik @org/platform-leads
   # /iac-live-repo/log-archive/       @org/security-team
   # /iac-live-repo/security-tooling/  @org/security-team
   # /iac-live-repo/network-hub/       @org/network-team
   # /iac-live-repo/workloads-prod/    @org/platform-team
   /scripts/                  @ok-karthik
   ```
8. Render every new leaf into `$SNAP/after/` (`render "$new" "$SNAP/after/$(echo "$new" | tr / _).json"`) and run
   `python3 $SNAP/compare.py $SNAP .` → **`46 stacks compared, 0 differences`**.

## Part 3 — `scripts/` at the repo root, script rewrites, the one-file check

Commit: `refactor(scripts): move to scripts/, follow the one-repo layout, check the one-file rule`

- `git mv workloads-live-repo/scripts scripts` (then `workloads-live-repo/` must not exist). Remove `scripts/__pycache__` / `scripts/tests/__pycache__` if tracked.
- Repo-root depth (M10): `parents[2]` → `parents[1]` in `check_policy_catalog.py`, `verify_module.py`, `generate_account_matrix.py`;
  `.parent.parent.parent` → `.parent.parent` in `check_discovery_contract.py`; `verify_module.py:42` → `REPO_ROOT / "scripts" / "run-checkov.sh"`.
  `grep -n 'dirname\|\.\./\.\.' scripts/*.sh` and fix any depth assumption the same way. Fix every usage/docstring line that says `workloads-live-repo/scripts`.
- `generate_account_matrix.py`: `LIVE_REPOS = ("iac-live-repo",)`; delete `OU_FOLDER`; `find_account_dir(root, name)` returns
  `root/"iac-live-repo"/name` if it's a directory, else `None`. Registry path → `iac-live-repo/_config/accounts.hcl` (and the local file).
  Output fields stay the same; `working_directory` becomes e.g. `iac-live-repo/workloads-dev`.
- `plan_scope.py`: `SHARED_PREFIXES` = `("iac-modules-repo/", "policy-library-repo/", ".github/", "iac-live-repo/_config/", "scripts/")`,
  `SHARED_FILES` = `("iac-live-repo/root.hcl", ".checkov.yaml", ".tflint.hcl")`. Update the docstring.
- `check-account-registry.sh`: rewrite. Every top-level folder in `iac-live-repo/` not starting with `_` must be a registry key; every folder
  below it must be `_global` or a region in `regions.hcl` `allowed_regions_by_ou[<that account's ou>]`. **One-file check:** fail if any
  `iac-live-repo/**/terragrunt.hcl` (excluding `.terragrunt-cache`) contains `read_terragrunt_config`, `get_env(`, or
  `find_in_parent_folders` on any line other than `path = find_in_parent_folders("root.hcl")`. One output line per failure; exit 1 on any.
  Read the registry with `python3 -c` + `parse_registry` from `scripts/generate_account_matrix.py`, not grep. Accept an optional first
  argument = root dir (default: repo root), so tests can point it at a temp tree.
- `smoke-test.sh`: default `ACCOUNT_DIR="iac-live-repo/workloads-dev"`; replace the `account.hcl`/`region.hcl` loops with a call to
  `scripts/check-account-registry.sh`; drop the `module_versions` comment; fix every old path.
- `generate-module.sh`: usage `generate-module.sh <category/module> <account> <region>`; writes one leaf at
  `iac-live-repo/<account>/<region>/<module>/terragrunt.hcl` from the template (`inputs = {}` with `# TODO: inputs`). Fail if the account folder is missing.
- `migrate-state-keys.sh`: `git rm` (it reads `account.hcl` and served the previous migration).
- `cost_report.py`, `cost_gate.py`, `merge_sarif.py`, `run-checkov.sh`, `check-licenses.sh`: fix only path strings, if any.
- `iac-live-repo/_bootstrap/bootstrap.sh`: lines 24-25 and 81-90. `REGION=$(hcl_value iac-live-repo/_config/regions.hcl primary_region)`;
  `OWNER`/`DATA_CLASSIFICATION` via
  `python3 -c 'import sys; sys.path.insert(0, "scripts"); from generate_account_matrix import parse_registry; print(parse_registry(open("iac-live-repo/_config/accounts.hcl").read())["management"]["owner"])'`
  (same for `data_classification`). The template/stack-policy paths and `LOCAL_ACCOUNTS_HCL` default move to `iac-live-repo/...`. Keep the
  "missing values" `fail`, naming the registry. Check `bash -n` and the bootstrap tests. **Never run bootstrap.sh** (it calls AWS).
- Tests: `scripts/tests/test_generate_account_matrix.py` (fixtures with `iac-live-repo/<name>` folders; remove OU-folder cases; add: a
  folder not in the registry is not matched), `test_plan_scope.py` (new prefixes), and a new `test_one_file_rule.py`: a temp tree with a leaf
  containing `read_terragrunt_config` → `check-account-registry.sh <tmp>` exits 1; a clean leaf → exits 0. Fix any test that hardcodes
  `workloads-live-repo`.

## Part 4 — CI, actions, Renovate, Infracost, pre-commit, Makefile

Commit: `ci: one live repo and scripts/; drop IAC_MODULES_LOCAL and module pins`

- Workflows (`terragrunt`, `reusable-terragrunt`, `drift-detection`, `destroy`, `finops-weekly`): delete `IAC_MODULES_LOCAL: '1'` and its comment
  block; `workloads-live-repo/scripts/` → `scripts/`; `foundation-live-repo/_config/accounts.hcl` → `iac-live-repo/_config/accounts.hcl` in comments; no `_envcommon` mentions.
- `.github/actions/setup-platform/action.yml:32,46-48`: write `iac-live-repo/_config/accounts.local.hcl` (`mkdir -p iac-live-repo/_config`).
- `.github/actions/static-analysis/action.yml`: fmt over `iac-modules-repo iac-live-repo policy-library-repo` (replace the two live-repo lines
  with one `terraform fmt -check -recursive iac-live-repo`); `tflint --chdir=iac-live-repo` (one line instead of two); `cfn-lint iac-live-repo/_bootstrap/cloudformation/*.yaml`;
  `unittest discover -s iac-live-repo/_bootstrap/tests` and `-s scripts/tests`; every `./workloads-live-repo/scripts/...` → `./scripts/...`.
- `.github/docker/Dockerfile` line 7 comment: `scripts/run-checkov.sh`.
- `infracost-config.yml`: `path: iac-live-repo/workloads-dev` / `iac-live-repo/workloads-prod`; drop the `_envcommon` excludes; keep `.terragrunt-cache`.
- `renovate.json`: remove the `env.hcl` and `tfr://` custom managers and the 20 `env.hcl` packageRules (M9); keep the rest. `python3 -m json.tool` must pass. Don't run `renovate-config-validator` (big download); list it under "not checked".
- `.pre-commit-config.yaml`: line 16 → `^iac-live-repo/_bootstrap/cloudformation/.*\.ya?ml$`; line 23 fmt roots → `iac-modules-repo iac-live-repo policy-library-repo`;
  lines 31, 43, 45 → `./scripts/...`; the `account.hcl` comment → "the registry".
- `Makefile`: `FMT_DIRS := iac-modules-repo iac-live-repo policy-library-repo`; lines 34, 38, 51 → `scripts/...`; `plan` target →
  `plan: ## Plan one account: make plan ACCOUNT=workloads-dev` with `cd iac-live-repo/$(ACCOUNT) && terragrunt run --all plan --non-interactive --log-format bare`.
  `make test`: add `python3 -m unittest discover -s scripts/tests` if it isn't run there yet (CI runs it via static-analysis).

## Part 5 — The IaC agent scaffolds one file in iac-live-repo

Commit: `refactor(iac-agent): scaffold one terragrunt.hcl per stack in iac-live-repo`

- `git mv iac-agents-repo/catalog/templates/<t>/envcommon.hcl.tmpl .../leaf.hcl.tmpl` (3 templates); rewrite each as the leaf template, keeping placeholders.
- `iac_agent.py` (≈ lines 254-318, 808-811, 864): write and `git add` only the leaf at `iac-live-repo/<account>/<region>/<module>/terragrunt.hcl`
  from `leaf.hcl.tmpl`. `live_env_dir("dev")` → `iac-live-repo/workloads-dev`, `"prod"` → `iac-live-repo/workloads-prod`. Every
  `workloads-live-repo`/`foundation-live-repo` string → the new path.
- `catalog/golden-paths.yaml`: point at `iac-modules-repo/storage/s3` instead of `_envcommon/data/s3.hcl`.
- `prompts/iac_agent.md` lines 11-16: describe the layout in 4 lines (`iac-live-repo/<account>/<region>/<stack>`; one file; values from
  `include.root.locals`; never `read_terragrunt_config`). `prompts/architect.md`, `prompts/ci_healer.md`, `README.md`: path strings only.
- Tests: `test_platform.py` (~27-30 paths, ~193 template name), `test_healer_guards.py:12` (`OK_PATHS` example → an `iac-live-repo/...` path).
- `python3 -m unittest discover -s iac-agents-repo/tests` must pass; also `python3 iac-agents-repo/scripts/iac_agent_eval.py` if that file exists.

## Part 6 — Docs and the migration note

Commit: `docs: one live repo with a flat, one-file layout`

- `AGENTS.md`: §1 layout (one live repo + `scripts/`; drop the two live-repo bullets), §3 commands (`make plan ACCOUNT=...`, `cd iac-live-repo/...`,
  `scripts/...`, fmt roots), §4 replaced by **"How a stack is put together"** (≤ 25 lines: folder rule, root.hcl's job, leaf template,
  where values come from, the one-file check), §6 CI paths, §7 gotchas (drop the `account.hcl`/`env.hcl` bullets; add "a value lives in
  exactly one place: the leaf, or the registry via root.hcl").
- `docs/adr/0001-repository-topology.md`: add a section `## 2026-10-11 revision: one live repo` starting with
  `> DRAFT by the model: the owner rewrites this in his own words.` Content: the two live repos are merged into `iac-live-repo/`;
  isolation between accounts comes from per-account CI roles (OIDC, plan/apply), per-account state buckets, and GitHub Environments with
  approvals, not from repo boundaries; ownership is CODEOWNERS per account folder; `iac-modules-repo` and `policy-library-repo` stay
  separately versioned; what we give up (one repo's history for both teams, per-repo branch protection); when to split again (separate
  teams with separate release cadences, or an audit need for repo-level separation).
- `docs/adr/0010-terragrunt-vs-plain-terraform.md`: status → `accepted (revised 2026-10-11)` (the "superseded by ADR 0009" is wrong). Add a
  `## 2026-10-11 revision: simple Terragrunt` section with the same DRAFT first line: the decision, what was removed (`_envcommon`,
  account/env/region files, module pins, two roots), what's kept and why, the bug it prevents (PR #71 `min_size`), the trade-off (2–4 similar leaves).
- `docs/adr/0012-terragrunt-stacks.md`: status `not used: superseded by the one-file layout (ADR 0010, 2026-10-11)`.
- Every other Part 6 file: replace old paths with the new ones (mapping table; `foundation-live-repo/_config` → `iac-live-repo/_config`,
  `foundation-live-repo/_bootstrap` → `iac-live-repo/_bootstrap`, `workloads-live-repo/scripts` → `scripts`) and the
  `env.hcl`/`account.hcl`/`region.hcl`/`_envcommon` wording with the new terms. In HTML files change only path strings and labels.
  In `bootstrap-stacksets/main.tf` and `variables.tf` change only the path in the line-2 comment/description; then
  `make verify-module MODULE=governance/bootstrap-stacksets` must be ok.
- New `docs/migrations/2026-10-simple-layout.md`: what changed (5 lines), the mapping table, and the **Owner: state move** section below verbatim.
- `docs/migrations/2026-single-to-multi-account.md`: one new first line `> Historical. The current layout: 2026-10-simple-layout.md.`

## Rules this task can break (copied from AGENTS.md and the owner)

1. No AWS credentials, never the default profile, offline only. Never `apply`/`destroy`/`import`/`state`/`force-unlock`/`--backend-bootstrap`. Every render uses the `env -u AWS_PROFILE ...` prefix (M6).
2. Never edit `.checkov.yaml`, `.claude/`, `policy-library-repo/`, `.trivyignore`, `PLAN.md`, `SIMPLIFY_PLAN.md`, `LEARNING_PLAN.md`, `learning/`, `docs/EXECUTION_LOG.md`. If one blocks you, stop and report.
3. `make verify-module` has a 3-failed-runs-per-module limit. Only Part 6's `bootstrap-stacksets` check needs it.
4. `terraform fmt -recursive iac-modules-repo iac-live-repo policy-library-repo` and `terragrunt hcl fmt` must leave no diff.
5. Never invent account ids, emails or values. Every input value comes from the baseline render.
6. Don't commit `.terragrunt-cache/`, `.terraform/`, `provider.tf`, `backend.tf`, `accounts.local.hcl` or anything under `$SNAP`.

## Verify sequence (end of Part 6; look at the output)

```bash
export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache
# 1. Same stacks, same inputs (the main check)
rm -f $SNAP/after/*; while IFS=$'\t' read -r old new; do render "$new" "$SNAP/after/$(echo "$new" | tr / _).json" || echo "FAIL $new"; done < $SNAP/mapping.tsv
python3 $SNAP/compare.py $SNAP .                                  # expect: "46 stacks compared, 0 differences"
# 2. Shape
ls foundation-live-repo workloads-live-repo 2>&1                   # both: No such file or directory
find iac-live-repo -name terragrunt.hcl -not -path '*/.terragrunt-cache/*' | wc -l                       # 46
find iac-live-repo \( -name account.hcl -o -name env.hcl -o -name region.hcl -o -name _envcommon \)       # nothing
ls iac-live-repo                                                    # account folders, _bootstrap, _config, root.hcl, README.md
ls iac-live-repo/_config/accounts.local.hcl && git check-ignore iac-live-repo/_config/accounts.local.hcl  # present and ignored
# 3. Nothing still points at the old layout
grep -rnE "foundation-live-repo|workloads-live-repo|_envcommon|env\.hcl|account\.hcl|region\.hcl|workloads/nonprod|workloads/prod|IAC_MODULES_LOCAL|module_versions" . \
  --exclude-dir=.git --exclude-dir=.terragrunt-cache --exclude-dir=.terraform --exclude-dir=learning --exclude-dir=plans --exclude-dir=.claude \
  --exclude=PLAN.md --exclude=SIMPLIFY_PLAN.md --exclude=LEARNING_PLAN.md --exclude=EXECUTION_LOG.md --exclude=CHANGELOG.md \
  --exclude=2026-single-to-multi-account.md --exclude=2026-10-simple-layout.md --exclude=.checkov.yaml \
  | grep -v "^./policy-library-repo/"
#    expect: nothing, except ADR 0001/0010 revision text that names the old layout on purpose. List every hit in the report.
# 4. Checks and tests
terraform fmt -check -recursive iac-modules-repo iac-live-repo policy-library-repo && terragrunt hcl fmt --check
bash scripts/check-account-registry.sh               # success line; then add read_terragrunt_config to one leaf, rerun → exit 1, git checkout the leaf
./scripts/smoke-test.sh                              # on iac-live-repo/workloads-dev; if it needs AWS, write that down and skip
python3 -m unittest discover -s scripts/tests -v 2>&1 | tail -15
python3 -m unittest discover -s iac-live-repo/_bootstrap/tests
python3 -m unittest discover -s iac-agents-repo/tests
python3 -m unittest discover -s .claude/hooks        # passes only after the owner's guard edit ("Owner: before" step 1)
make test
grep -n "iac-live-repo" .checkov.yaml || echo "STOP: owner step 2 not done; skip make checkov and report"
make checkov                                          # only if the line above found iac-live-repo
# 5. Matrix still works (no AWS)
python3 scripts/generate_account_matrix.py            # every working_directory is iac-live-repo/<account>; same accounts as before the change
# 6. Hygiene
python3 -m json.tool renovate.json >/dev/null && echo json-ok
git status --short                                    # clean: no .terragrunt-cache, .terraform, provider.tf, backend.tf, accounts.local.hcl
git log --oneline main..HEAD                          # 6 commits (Parts 1-6)
```

## Done means

- [ ] 6 commits on `refactor/simple-terragrunt`, messages as given. Nothing pushed.
- [ ] `46 stacks compared, 0 differences`.
- [ ] `foundation-live-repo/` and `workloads-live-repo/` are gone; `iac-live-repo/` has one `root.hcl`, `_config/`, `_bootstrap/`, 46 one-file leaves; `scripts/` at the root.
- [ ] No old-layout references left outside the allowed files (verify step 3).
- [ ] The one-file check fails on a bad leaf and passes on the repo; all tests, `make test` green; `make checkov` green or explicitly blocked on owner step 2.

**Report back:** commit list; the compare script's last line and any script fix you made; each verify step's output; every deviation and why;
the owner steps still open; a **"not checked"** list (at least: anything needing AWS, the Renovate config validator, the workflows on GitHub).

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

## Owner follow-ups (comments in human-only files; nothing breaks if they wait)

- `policy-library-repo/POLICIES.md:4`: `workloads-live-repo/scripts/check_policy_catalog.py` → `scripts/check_policy_catalog.py`.
- `policy-library-repo/terraform/deny_member_org_admin.rego:6`: `foundation-live-repo/_bootstrap/...` → `iac-live-repo/_bootstrap/...`.
- `policy-library-repo/terraform/require_tags.rego:7`: the comment says tags come "from account.hcl" → "from the registry via root.hcl".
- `.claude/hooks/guard.py`: once the migration is merged, drop the old-path fallback from "Owner: before" step 1.
- `.claude/hooks/test_guard.py:56`: the example `cd workloads-live-repo/workloads/prod/workloads-prod && terragrunt apply` still tests the block correctly; update the path for readability if you like.

## Out of scope

- Changing modules in `iac-modules-repo/` (beyond the path text in bootstrap-stacksets and module READMEs), release-please, or the release tags.
- Pinning prod to release tags again: revisit only if live config and modules are ever split into separate repos.
- Digger and OpenTofu (parked in PLAN.md 8.11 / 8.12).
- The remaining PR #71 review findings that weren't fixed (if any): a separate fix-up.
