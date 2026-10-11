# Plan: simple Terragrunt, one file per stack, flat folders

- **Written:** 2026-10-11 by Claude Opus 5.5 (planner). **Executor:** the `implementer` agent (Sonnet tier).
- **Branch:** `refactor/simple-terragrunt` from `main`, **after PR #71 (PLAN 9.5) is merged with its review fixes** (Part 0 checks this).
- **One commit per part**, messages as given. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Do NOT:** push, open a PR, merge, use AWS credentials or the shell's default AWS profile, run `apply`/`destroy`/`import`/`state`/`force-unlock`,
  run `--backend-bootstrap`, or touch the S3 state. The state move is the **owner's** job (last section).
- Always `export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache` first (mobile data: never re-download the AWS provider).

## Goal

Today, to understand one stack you open the leaf, `root.hcl`, an `_envcommon` file, `env.hcl`, `account.hcl`, `region.hcl` and the registry
(287 lookups). This hid a real bug in PR #71 (dev EKS `min_size` set in two files). After this task:

- **The folder path is the config:** `<repo>/<account>/<region or _global>/<stack>/terragrunt.hcl`.
- **Each `terragrunt.hcl` is the whole stack:** module source, dependencies, every input. The only thing it includes is `root.hcl`.
- **`root.hcl` is the only file that looks anything up:** account from the path, everything else from the registry.

Terragrunt keeps doing what it's good at: generating provider and backend, state key from the path, `dependency` with mock outputs, and `run --all`.

## Scope (only these may change)

| Part | Files |
|---|---|
| 1 | `foundation-live-repo/_config/accounts.hcl`, `foundation-live-repo/_config/accounts.local.hcl.example` |
| 2 | everything under `foundation-live-repo/` except `_bootstrap/` and `_config/` |
| 3 | everything under `workloads-live-repo/` except `scripts/` |
| 4 | `workloads-live-repo/scripts/**` (incl. `tests/`), `foundation-live-repo/_bootstrap/bootstrap.sh` |
| 5 | `.github/workflows/{terragrunt,reusable-terragrunt,drift-detection,destroy}.yml`, `infracost-config.yml`, `renovate.json`, `.pre-commit-config.yaml`, `Makefile` |
| 6 | `iac-agents-repo/iac_agent/iac_agent.py`, `iac-agents-repo/catalog/**`, `iac-agents-repo/prompts/iac_agent.md`, `iac-agents-repo/tests/{test_platform,test_healer_guards}.py` |
| 7 | `AGENTS.md`, `docs/{CICD,ARCHITECTURE,GOVERNANCE,COMPLIANCE,DISASTER_RECOVERY,FINOPS}.md`, `docs/runbooks/drill-bad-scp-rollback.md`, `docs/adr/{0001,0010,0012}-*.md`, `docs/visualizer.html`, `.github/assets/visualizer.html`, `.github/CONTRIBUTING.md`, `foundation-live-repo/_bootstrap/README.md`, `iac-modules-repo/governance/bootstrap-stacksets/README.md`, `iac-modules-repo/security/org-cloudtrail/README.md`, new `docs/migrations/2026-10-simple-layout.md`, first line only of `docs/migrations/2026-single-to-multi-account.md` |

**Never edit:** `policy-library-repo/` (its `require_tags.rego:7` comment mentions `account.hcl`: owner follow-up), `.claude/`
(`test_guard.py:56` is only a command string and needs no change), `.checkov.yaml`, `.trivyignore`, `PLAN.md`, `SIMPLIFY_PLAN.md`,
`LEARNING_PLAN.md`, `learning/`, `docs/EXECUTION_LOG.md`, `iac-modules-repo/**/*.tf`.

## What was measured — do not re-derive (2026-10-11)

| # | Fact |
|---|---|
| M1 | 46 leaf `terragrunt.hcl` files (incl. the 9.5 `cost-janitor` leaf). 29 `_envcommon` files; `_envcommon/data/s3.hcl` has **0** users (it's the only `tfr://` source). |
| M2 | For every account, folder name == registry key == `account_name` in `account.hcl`. Every region folder name == the `aws_region` in its `region.hcl`. Both `_global/region.hcl` say `eu-central-1` == `regions.hcl` `primary_region`. So deriving account and region from the path gives exactly the same values. |
| M3 | Both `root.hcl` copies are identical (diff of non-comment lines is empty). Today root uses the registry `id` first (`try(account_entry.id, account.hcl id)`), so dropping `account.hcl` doesn't change `account_id`. |
| M4 | `accounts.hcl` builds `accounts = { for name, base in local.base_accounts : name => merge(base, try(local.local_accounts[name], {})) }`. `generate_account_matrix.parse_registry` reads flat `key = "value"` lines per account, so new flat string fields are picked up automatically. |
| M5 | Values leaves read today: `env_vars.module_versions` ×49, `region_vars.aws_region` ×23, `account_vars.account_name` ×14, `account_vars.env` ×10, `env_vars.env` ×9, `env_vars.cluster_name` ×8, `account_vars.aws_account_id` ×7, `env_vars.api_allowed_cidrs` ×4, `account_vars.{owner,ou,data_classification,account_alias}` ×4 each, `env_vars.{single_nat_gateway,min_size,enable_nat_gateway,desired_size}` ×2, `env_vars.scale_schedule` ×1. Plus 40 `read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/...")` reads of the registry/regions/organization. |
| M6 | `terragrunt render --format json` works **offline for all 46 leaves** (exit 0; dependency outputs fall back to `mock_outputs`) with `env -u AWS_PROFILE AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null IAC_MODULES_LOCAL=1`. It needs the local, gitignored `foundation-live-repo/_config/accounts.local.hcl` (present on this machine). Its output has `.inputs`, `.terraform.source`, `.generate`, `.remote_state.config`, `.dependency`. |
| M7 | All four workflows already set `IAC_MODULES_LOCAL: '1'`, and the owner's Gemini applies used it too, so the deployed code is always the local `iac-modules-repo`. Many release tags don't exist (e.g. billing, org-cloudtrail, guardrail-signals). **Local source everywhere = no behaviour change.** |
| M8 | `_envcommon/governance/billing.hcl` has an extra `generate` block (the `us_east_1` provider alias). It's the only extra `generate`. |
| M9 | `renovate.json`: custom managers = Dockerfile ARGs (keep), `env.hcl` module pins (remove), `tfr://` modules (remove; only user is the dead s3.hcl). 23 `packageRules`: 20 have `matchFileNames` on an `env.hcl` (remove), 3 don't (keep). |
| M10 | `generate_account_matrix.py` has `OU_FOLDER` and `find_account_dir` (tries `<repo>/<ou_folder>/<name>`, then `<repo>/<name>`). `bootstrap.sh:24-25` reads `management/account.hcl` and `management/_global/region.hcl`; `:81-90` reads `owner`, `data_classification`, `aws_region` from them. `Makefile:55` `plan` target does `cd workloads-live-repo/workloads/$(ENV)`. |
| M11 | The owner applied 5 stacks (keys in bucket `tg-state-954171757349-eu-central-1`): `management/_global/governance/{organization,account-factory,bootstrap-stacksets}`, `management/eu-central-1/identity/identity-center`, `management/eu-central-1/governance/budgets`. Their state keys change with the new paths. **The implementer does not touch them**; the owner moves them (last section). |

## Decisions already made (don't reopen)

- **Account = path segment 0, region = segment 1 (`_global` → `primary_region`).** Delete every `account.hcl`, `env.hcl`, `region.hcl` and all of `_envcommon/`.
- **Registry is the single source of truth.** It gains `alias`, `owner`, `data_classification` per account (copied from today's `account.hcl`).
- **Module source is always the local folder** (`${get_repo_root()}/iac-modules-repo/<category>/<module>`). `module_versions`, `IAC_MODULES_LOCAL` and Renovate's module-pin rules go. Release tags stay (release-please is untouched) for outside consumers such as `internal-developer-platform`.
- **State key stays `path_relative_to_include()`**, so it follows the new shorter paths. The default tag `Service` is that same path and changes too. That's expected and gives in-place tag updates only.
- **The one-file rule becomes a test** (Part 4), so a value can't hide in a second file again.

## Old → new paths (all 46; no collisions)

| Old leaf folder | New leaf folder |
|---|---|
| `foundation-live-repo/infrastructure/network-hub/_global/network/ipam` | `foundation-live-repo/network-hub/_global/ipam` |
| `foundation-live-repo/infrastructure/network-hub/eu-central-1/network/dns` | `foundation-live-repo/network-hub/eu-central-1/dns` |
| `foundation-live-repo/infrastructure/network-hub/eu-central-1/network/inspection-egress` | `foundation-live-repo/network-hub/eu-central-1/inspection-egress` |
| `foundation-live-repo/infrastructure/network-hub/eu-central-1/network/tgw-peering` | `foundation-live-repo/network-hub/eu-central-1/tgw-peering` |
| `foundation-live-repo/infrastructure/network-hub/eu-central-1/network/transit-gateway` | `foundation-live-repo/network-hub/eu-central-1/transit-gateway` |
| `foundation-live-repo/infrastructure/network-hub/eu-west-1/network/dns` | `foundation-live-repo/network-hub/eu-west-1/dns` |
| `foundation-live-repo/infrastructure/network-hub/eu-west-1/network/inspection-egress` | `foundation-live-repo/network-hub/eu-west-1/inspection-egress` |
| `foundation-live-repo/infrastructure/network-hub/eu-west-1/network/tgw-peering` | `foundation-live-repo/network-hub/eu-west-1/tgw-peering` |
| `foundation-live-repo/infrastructure/network-hub/eu-west-1/network/transit-gateway` | `foundation-live-repo/network-hub/eu-west-1/transit-gateway` |
| `foundation-live-repo/infrastructure/observability/eu-central-1/observability/guardrail-signals` | `foundation-live-repo/observability/eu-central-1/guardrail-signals` |
| `foundation-live-repo/infrastructure/observability/eu-central-1/observability/oam` | `foundation-live-repo/observability/eu-central-1/oam` |
| `foundation-live-repo/infrastructure/shared-services/eu-central-1/network/central-endpoints` | `foundation-live-repo/shared-services/eu-central-1/central-endpoints` |
| `foundation-live-repo/management/_global/governance/account-factory` | `foundation-live-repo/management/_global/account-factory` |
| `foundation-live-repo/management/_global/governance/bootstrap-stacksets` | `foundation-live-repo/management/_global/bootstrap-stacksets` |
| `foundation-live-repo/management/_global/governance/data-perimeter` | `foundation-live-repo/management/_global/data-perimeter` |
| `foundation-live-repo/management/_global/governance/organization` | `foundation-live-repo/management/_global/organization` |
| `foundation-live-repo/management/eu-central-1/governance/account-baseline` | `foundation-live-repo/management/eu-central-1/account-baseline` |
| `foundation-live-repo/management/eu-central-1/governance/billing` | `foundation-live-repo/management/eu-central-1/billing` |
| `foundation-live-repo/management/eu-central-1/governance/budgets` | `foundation-live-repo/management/eu-central-1/budgets` |
| `foundation-live-repo/management/eu-central-1/identity/identity-center` | `foundation-live-repo/management/eu-central-1/identity-center` |
| `foundation-live-repo/management/eu-central-1/observability/guardrail-signals` | `foundation-live-repo/management/eu-central-1/guardrail-signals` |
| `foundation-live-repo/management/eu-central-1/security/break-glass-alerts` | `foundation-live-repo/management/eu-central-1/break-glass-alerts` |
| `foundation-live-repo/management/eu-central-1/security/org-cloudtrail` | `foundation-live-repo/management/eu-central-1/org-cloudtrail` |
| `foundation-live-repo/management/eu-central-1/security/security-alerts` | `foundation-live-repo/management/eu-central-1/security-alerts` |
| `foundation-live-repo/security/log-archive/eu-central-1/security/log-archive` | `foundation-live-repo/log-archive/eu-central-1/log-archive` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/access-analyzer` | `foundation-live-repo/security-tooling/eu-central-1/access-analyzer` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/auto-remediation` | `foundation-live-repo/security-tooling/eu-central-1/auto-remediation` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/firewall-manager` | `foundation-live-repo/security-tooling/eu-central-1/firewall-manager` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/org-config` | `foundation-live-repo/security-tooling/eu-central-1/org-config` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/security-alerts` | `foundation-live-repo/security-tooling/eu-central-1/security-alerts` |
| `foundation-live-repo/security/security-tooling/eu-central-1/security/threat-detection` | `foundation-live-repo/security-tooling/eu-central-1/threat-detection` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/compute/eks` | `workloads-live-repo/workloads-dev/eu-central-1/eks` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/account-baseline` | `workloads-live-repo/workloads-dev/eu-central-1/account-baseline` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/budgets` | `workloads-live-repo/workloads-dev/eu-central-1/budgets` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/cost-janitor` | `workloads-live-repo/workloads-dev/eu-central-1/cost-janitor` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/discovery-publisher` | `workloads-live-repo/workloads-dev/eu-central-1/discovery-publisher` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/network/vpc` | `workloads-live-repo/workloads-dev/eu-central-1/vpc` |
| `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/security/break-glass-alerts` | `workloads-live-repo/workloads-dev/eu-central-1/break-glass-alerts` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/compute/eks` | `workloads-live-repo/workloads-prod/eu-central-1/eks` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/governance/account-baseline` | `workloads-live-repo/workloads-prod/eu-central-1/account-baseline` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/governance/budgets` | `workloads-live-repo/workloads-prod/eu-central-1/budgets` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/governance/discovery-publisher` | `workloads-live-repo/workloads-prod/eu-central-1/discovery-publisher` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/network/vpc` | `workloads-live-repo/workloads-prod/eu-central-1/vpc` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-central-1/security/break-glass-alerts` | `workloads-live-repo/workloads-prod/eu-central-1/break-glass-alerts` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-west-1/compute/eks` | `workloads-live-repo/workloads-prod/eu-west-1/eks` |
| `workloads-live-repo/workloads/prod/workloads-prod/eu-west-1/network/vpc` | `workloads-live-repo/workloads-prod/eu-west-1/vpc` |

## The new `root.hcl` (write exactly this into BOTH `foundation-live-repo/root.hcl` and `workloads-live-repo/root.hcl`)

```hcl
# root.hcl: included by every stack (terragrunt.hcl) in this live repo. Kept identical in foundation-live-repo and
# workloads-live-repo (separate repos in a real company cannot share a file).
#
# The folder path IS the configuration:
#   <account>/<region or _global>/<stack>/terragrunt.hcl
#   - <account> must be a key in foundation-live-repo/_config/accounts.hcl (the registry)
#   - <region> is an AWS region; _global means "account-wide", run from the primary region
#
# This is the ONLY file that looks anything up. A stack reads these values as include.root.locals.<name>.
locals {
  path_parts   = split("/", path_relative_to_include())
  account_name = local.path_parts[0]
  region_dir   = local.path_parts[1]

  registry     = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl").locals.accounts
  regions      = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/regions.hcl").locals
  organization = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/organization.hcl").locals

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

Before writing it, compare with today's `root.hcl`. If today's file has any other block or setting not shown here, **keep it unchanged**
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

3. Keep the "why" comments from `_envcommon` and the old leaf (attach them to the input they explain). Drop comments that only explain the old layering.
4. `billing`: copy `_envcommon/governance/billing.hcl`'s `generate` block into the billing leaf unchanged.
5. A dependency that points to a stack in **another** account or region: compute the relative path between the two **new** folders
   (e.g. `../../eu-west-1/tgw-peering`). Check it resolves: `ls <new leaf>/<config_path>/terragrunt.hcl`.
6. No `read_terragrunt_config`, no `find_in_parent_folders` (except in the `include "root"` block), no `get_env`.

## Part 0 — Preconditions and the baseline render (no commit)

```bash
export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache
cd /Users/karthik.orugonda/github/enterprise-aws-infrastructure
git switch main && git pull --ff-only
git log --oneline main | grep -c "PLAN 9.5"            # must be >= 7, else STOP: PR #71 is not merged
test -f foundation-live-repo/_config/accounts.local.hcl || echo STOP   # render needs it (M6)
SNAP=/private/tmp/claude-501/simple-tg; rm -rf $SNAP; mkdir -p $SNAP/before $SNAP/after
awk -F'`' '/^\| `(foundation|workloads)-live-repo\//{print $2"\t"$4}' docs/plans/2026-10-11-simple-terragrunt.md > $SNAP/mapping.tsv; wc -l < $SNAP/mapping.tsv   # 46
render() {  # $1 = leaf dir, $2 = output file
  (cd "$1" && env -u AWS_PROFILE AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null IAC_MODULES_LOCAL=1 \
     timeout 120 terragrunt render --format json --non-interactive --log-format bare > "$2" 2>"$2.err")
}
while IFS=$'\t' read -r old new; do render "$old" "$SNAP/before/$(echo "$old" | tr / _).json" || echo "FAIL $old"; done < $SNAP/mapping.tsv
jq -c '.inputs | {min_size, scale_schedule}' $SNAP/before/workloads-live-repo_workloads_nonprod_workloads-dev_eu-central-1_compute_eks.json
```
**STOP** if any render fails, if `git log` lacks the 9.5 commits, or if the dev EKS line shows `"min_size":1` together with a non-null
`scale_schedule` (the PR #71 review fix isn't in). Then `git switch -c refactor/simple-terragrunt`.

Save this script as `$SNAP/compare.py` (scratch, not committed):

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
    if b["inputs"] != a["inputs"]:
        for k in sorted(set(b["inputs"]) | set(a["inputs"])):
            if b["inputs"].get(k) != a["inputs"].get(k): bad(new, f"input {k}: {b['inputs'].get(k)!r} -> {a['inputs'].get(k)!r}")
    if b["terraform"]["source"] != a["terraform"]["source"]: bad(new, f"source {b['terraform']['source']} -> {a['terraform']['source']}")
    if set(b["generate"]) != set(a["generate"]): bad(new, f"generate blocks {sorted(b['generate'])} -> {sorted(a['generate'])}")
    for g in b["generate"]:
        bc, ac = b["generate"][g]["contents"], a["generate"].get(g, {}).get("contents", "")
        if (norm_provider(bc) if g == "provider" else bc) != (norm_provider(ac) if g == "provider" else ac): bad(new, f"generate {g} contents differ")
    m = re.search(r'Service\s*=\s*"([^"]*)"', a["generate"]["provider"]["contents"])
    want = new.split("/", 1)[1]
    if not m or m.group(1) != want: bad(new, f"Service tag {m and m.group(1)!r} != {want!r}")
    rb, ra = b["remote_state"]["config"], a["remote_state"]["config"]
    for k in ("bucket", "region", "encrypt", "use_lockfile"):
        if rb.get(k) != ra.get(k): bad(new, f"remote_state {k}: {rb.get(k)} -> {ra.get(k)}")
    if ra.get("key") != new.split("/", 1)[1] + "/terraform.tfstate": bad(new, f"state key {ra.get('key')}")
    bdeps, adeps = b.get("dependency") or {}, a.get("dependency") or {}
    if set(bdeps) != set(adeps): bad(new, f"dependencies {sorted(bdeps)} -> {sorted(adeps)}")
    for d in bdeps:
        if d not in adeps: continue
        bt = os.path.relpath(os.path.realpath(bdeps[d]["config_path"]), repo)
        at = os.path.relpath(os.path.realpath(adeps[d]["config_path"]), repo)
        if old_to_new.get(bt) != at: bad(new, f"dependency {d}: {bt} should map to {old_to_new.get(bt)}, got {at}")
        if bdeps[d].get("mock_outputs") != adeps[d].get("mock_outputs"): bad(new, f"dependency {d} mock_outputs differ")
print(f"{len(pairs)} stacks compared, {errors} differences"); sys.exit(1 if errors else 0)
```
(The key and `Service` checks use the path **inside** the live repo, e.g. `management/_global/organization`, which is what
`path_relative_to_include()` returns.) If a field name in the render JSON differs from what this script expects, fix the script
in scratch, don't relax a check, and mention it in the report.

## Part 1 — Registry gets alias, owner, data_classification

Commit: `refactor(config): registry carries alias, owner and data classification per account`

For every account in `base_accounts` in `foundation-live-repo/_config/accounts.hcl`, add three lines copied from that account's
`account.hcl`: `alias = "<account_alias>"`, `owner = "<owner>"`, `data_classification = "<data_classification>"`. Keep their `TODO(owner)` comments.
Align with `terragrunt hcl fmt`. Add the three fields to the field list in the file's header comment and to `accounts.local.hcl.example`'s comment
(no values). Nothing reads them yet: re-render 3 leaves and check they're unchanged.

## Part 2 — foundation-live-repo: new root, flat folders, one file per stack

Commit: `refactor(foundation)!: one terragrunt.hcl per stack, account and region from the path`

1. Replace `foundation-live-repo/root.hcl` with the new root above.
2. For each foundation row of the mapping table: `git mv <old> <new>` (create the parent folder first). This keeps `.terraform.lock.hcl` and history.
3. Rewrite each moved `terragrunt.hcl` with the leaf template and the fill rules.
4. `git rm` every `account.hcl`, `env.hcl`, `region.hcl` under `foundation-live-repo/` and the whole `foundation-live-repo/_envcommon/`.
   Remove the now-empty `infrastructure/` and `security/` folders and the old category folders. Delete any `.terragrunt-cache`.
5. Render every new foundation leaf into `$SNAP/after/` (same `render` function, new path) and run
   `python3 $SNAP/compare.py $SNAP .`. Foundation rows must show **0 differences**. Workloads rows will be missing at this point:
   run the compare on a filtered copy of `mapping.tsv` (foundation lines only).

## Part 3 — workloads-live-repo: same

Commit: `refactor(workloads)!: one terragrunt.hcl per stack, account and region from the path`

Same steps as Part 2 for the workloads rows: copy the new root (identical: `diff foundation-live-repo/root.hcl workloads-live-repo/root.hcl` → no output),
`git mv`, rewrite, delete `workloads-live-repo/workloads/`, `workloads-live-repo/_envcommon/` (incl. `data/s3.hcl`, M1) and every
`account.hcl`/`env.hcl`/`region.hcl`. Then run the full compare: **`46 stacks compared, 0 differences`**.

## Part 4 — Scripts, bootstrap, tests, and the one-file rule as a check

Commit: `refactor(scripts): follow the flat layout; check the one-file rule`

- `generate_account_matrix.py`: delete `OU_FOLDER`. `find_account_dir(root, name)` returns `root/<repo>/<name>` for the first live repo where it's a directory, else `None`. Update the call site and docstrings. Output fields stay the same; `working_directory` becomes e.g. `workloads-live-repo/workloads-dev`.
- `plan_scope.py`: remove the two `_envcommon/` prefixes from `SHARED_PREFIXES` and the docstring mention.
- `check-account-registry.sh`: rewrite. For each live repo, every top-level folder not starting with `_` and not `scripts` must be a registry key. Every folder below it must be `_global` or a region in `regions.hcl` `allowed_regions_by_ou[<that account's ou>]`. **New one-file check:** fail if any `terragrunt.hcl` (excluding `.terragrunt-cache`) contains `read_terragrunt_config`, `get_env(`, or `find_in_parent_folders` on any line other than the `path = find_in_parent_folders("root.hcl")` line. Print one line per failure; exit 1 on any. Read the registry with `python3 -c` + `parse_registry` (import from `generate_account_matrix.py`), not with grep.
- `smoke-test.sh`: default `ACCOUNT_DIR="workloads-live-repo/workloads-dev"`. Replace the `account.hcl` / `region.hcl` loops (≈ lines 40-75) with a call to `check-account-registry.sh`. Remove the `module_versions` comment block (≈ line 22).
- `generate-module.sh`: usage `generate-module.sh <category/module> <account> <region>`. Write one leaf at `workloads-live-repo/<account>/<region>/<module>/terragrunt.hcl` from the template (include root + local source + `inputs = {}` with a `# TODO: inputs` comment). Fail if the account folder doesn't exist. Remove the `_envcommon` hint.
- `migrate-state-keys.sh`: `git rm` (it reads `account.hcl` and was for the previous migration; the new migration doc replaces it).
- `bootstrap.sh`: replace `ACCOUNT_HCL`/`REGION_HCL` (lines 24-25) and their reads (81-90) with:
  `REGION=$(hcl_value foundation-live-repo/_config/regions.hcl primary_region)`, and
  `OWNER` / `DATA_CLASSIFICATION` from `python3 -c 'import sys; sys.path.insert(0, "workloads-live-repo/scripts"); from generate_account_matrix import parse_registry; print(parse_registry(open("foundation-live-repo/_config/accounts.hcl").read())["management"]["owner"])'` (same for `data_classification`). Keep the "missing values" `fail` message, naming the registry instead. Run `bash -n bootstrap.sh` and `python3 -m unittest discover -s foundation-live-repo/_bootstrap/tests`. **Don't run bootstrap.sh** (it calls AWS).
- Tests: update `tests/test_generate_account_matrix.py` (fixtures use `<repo>/<name>` folders; remove OU-folder cases; add one case: an account folder that isn't in the registry is not matched), and `tests/test_plan_scope.py` (no `_envcommon` cases). Add `tests/test_one_file_rule.py`: write a temp `terragrunt.hcl` with a `read_terragrunt_config` line and assert `check-account-registry.sh` (run with a `ROOT` env var or argument you add, pointing at a temp tree) exits 1; a clean leaf exits 0.

## Part 5 — CI, Renovate, Infracost, pre-commit, Makefile

Commit: `ci: drop IAC_MODULES_LOCAL and module pins; follow the flat layout`

- The 4 workflows: delete the `IAC_MODULES_LOCAL: '1'` env line and its comment block. Fix any `_envcommon` mention in comments (`reusable-terragrunt.yml:67`).
- `infracost-config.yml`: `path: workloads-live-repo/workloads-dev` / `workloads-live-repo/workloads-prod`. Remove the `**/_envcommon/**` excludes; keep `.terragrunt-cache`.
- `renovate.json`: remove the `env.hcl` custom manager, the `tfr://` custom manager, and the 20 `packageRules` whose `matchFileNames` point at an `env.hcl` (M9). Keep everything else. `python3 -m json.tool renovate.json` must pass. Don't run `renovate-config-validator` (it downloads a lot on mobile data); list it under "not checked".
- `.pre-commit-config.yaml`: fix the comment that mentions `account.hcl` (say "the registry").
- `Makefile` `plan` target: `plan: ## Plan one account: make plan ACCOUNT=workloads-dev` and `cd workloads-live-repo/$(ACCOUNT) && terragrunt run --all plan --non-interactive --log-format bare`.

## Part 6 — The IaC agent scaffolds one file

Commit: `refactor(iac-agent): scaffold one terragrunt.hcl per stack`

- `git mv iac-agents-repo/catalog/templates/<t>/envcommon.hcl.tmpl .../leaf.hcl.tmpl` for all 3 templates. Rewrite each as the leaf template (include root, local source, inputs), keeping their placeholders.
- `iac_agent.py`: every place that builds `workloads-live-repo/_envcommon/<module>.hcl` (≈ lines 254-318, 808-811, 864) now writes and `git add`s only the leaf at `workloads-live-repo/<account>/<region>/<module>/terragrunt.hcl`, rendered from `leaf.hcl.tmpl`. `live_env_dir("dev")` → `workloads-live-repo/workloads-dev`, `"prod"` → `workloads-live-repo/workloads-prod`.
- `catalog/golden-paths.yaml`: replace the `_envcommon/data/s3.hcl` reference with the module path `iac-modules-repo/storage/s3`.
- `prompts/iac_agent.md` lines 11-16: describe the new layout in 4 lines (folder = account/region/stack; one file; values from `include.root.locals`; never `read_terragrunt_config`).
- Tests: `test_platform.py` (paths at lines ~27-30; the template file name at ~193), `test_healer_guards.py` line 12 (`OK_PATHS` example path → `workloads-live-repo/workloads-dev/eu-central-1/vpc/terragrunt.hcl` or similar).
- `python3 -m unittest discover -s iac-agents-repo/tests` and `python3 iac-agents-repo/scripts/iac_agent_eval.py` if it exists (check `ls`) must pass.

## Part 7 — Docs and the migration note

Commit: `docs: describe the flat, one-file layout`

- `AGENTS.md`: §1 layout bullets, §3 commands (`make plan ACCOUNT=...`, the example `cd` paths), §4 replaced by **"How a stack is put together"**
  (≤ 25 lines: the folder rule, root.hcl's job, the leaf template, where values come from, the one-file check), §7 gotchas
  (remove the `account.hcl`/`env.hcl` bullets; add "a value lives in exactly one place: the leaf, or the registry via root.hcl").
- Every other file in the Part 7 scope row: replace old paths using the mapping table, and `env.hcl`/`account.hcl`/`region.hcl`/`_envcommon`
  wording with the new terms. For `visualizer.html` ×2, only change path strings and labels.
- `docs/adr/0010-terragrunt-vs-plain-terraform.md`: fix the wrong "superseded by ADR 0009" status to `accepted (revised 2026-10-11)`. Add a
  section "2026-10-11 revision: simple Terragrunt", with the decision, what was removed (`_envcommon`, account/env/region files, module pins),
  what is kept and why, the bug it prevents (PR #71 `min_size`), and the trade-off (2–4 copies of similar leaves). First line of that section:
  `> DRAFT by the model: the owner rewrites this in his own words.`
- `docs/adr/0012-terragrunt-stacks.md`: status `not used: superseded by the one-file layout (ADR 0010, 2026-10-11)`.
- New `docs/migrations/2026-10-simple-layout.md`: copy the **Owner: state move** section below, plus the mapping table.
- `docs/migrations/2026-single-to-multi-account.md`: add one first line: `> Historical. The current layout is described in 2026-10-simple-layout.md.`

## Rules this task can break (copied from AGENTS.md and the owner)

1. No AWS credentials, never the default profile, offline only. Never `apply`/`destroy`/`import`/`state`/`force-unlock`, never `--backend-bootstrap`. Every render uses the `env -u AWS_PROFILE ...` prefix from M6.
2. Never edit `.checkov.yaml`, `.trivyignore`, `policy-library-repo/`, `.claude/`. Never edit `PLAN.md`, `SIMPLIFY_PLAN.md`, `LEARNING_PLAN.md`, `learning/`, `docs/EXECUTION_LOG.md` (owner-local files).
3. `make verify-module` has a 3-failed-runs-per-module limit; this task changes no module `.tf`, so you shouldn't need it.
4. `terraform fmt -recursive` over all four roots and `terragrunt hcl fmt` must leave no diff.
5. Never invent account ids, emails or values. Every input value comes from the baseline render.
6. Don't commit `.terragrunt-cache/`, `.terraform/`, `provider.tf`, `backend.tf` or anything under `$SNAP`.

## Verify sequence (end of Part 7; look at the output)

```bash
export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache
# 1. Same stacks, same inputs (the main check)
while IFS=$'\t' read -r old new; do render "$new" "$SNAP/after/$(echo "$new" | tr / _).json" || echo "FAIL $new"; done < $SNAP/mapping.tsv
python3 $SNAP/compare.py $SNAP .                                   # expect: "46 stacks compared, 0 differences"
# 2. Shape
find foundation-live-repo workloads-live-repo -name terragrunt.hcl -not -path '*/.terragrunt-cache/*' | wc -l          # 46
find foundation-live-repo workloads-live-repo \( -name account.hcl -o -name env.hcl -o -name region.hcl -o -name _envcommon \) -not -path '*/.terragrunt-cache/*'   # nothing
ls foundation-live-repo workloads-live-repo                         # only account folders, _bootstrap, _config, root.hcl, README/CODEOWNERS, scripts
diff foundation-live-repo/root.hcl workloads-live-repo/root.hcl     # nothing
# 3. Nothing still points at the old layout
grep -rnE "_envcommon|env\.hcl|account\.hcl|region\.hcl|workloads/nonprod|workloads/prod|IAC_MODULES_LOCAL|module_versions" . \
  --exclude-dir=.git --exclude-dir=.terragrunt-cache --exclude-dir=.terraform --exclude-dir=learning --exclude-dir=plans \
  --exclude=PLAN.md --exclude=SIMPLIFY_PLAN.md --exclude=LEARNING_PLAN.md --exclude=EXECUTION_LOG.md \
  --exclude=2026-single-to-multi-account.md --exclude=CHANGELOG.md | grep -v "^./policy-library-repo/terraform/require_tags.rego:7:" | grep -v "^./.claude/"
#    expect: nothing, or only lines in 2026-10-simple-layout.md that describe the old layout. List any other hit in the report.
# 4. Checks and tests
terraform fmt -check -recursive iac-modules-repo foundation-live-repo workloads-live-repo policy-library-repo && terragrunt hcl fmt --check
bash workloads-live-repo/scripts/check-account-registry.sh          # expect the success line; then add read_terragrunt_config to one leaf, rerun → exit 1, revert
./workloads-live-repo/scripts/smoke-test.sh                          # on workloads-dev; if it needs AWS, write that down and skip
python3 -m unittest discover -s workloads-live-repo/scripts/tests -v 2>&1 | tail -15
python3 -m unittest discover -s foundation-live-repo/_bootstrap/tests
python3 -m unittest discover -s iac-agents-repo/tests
python3 -m unittest discover -s .claude/hooks
make test
make checkov
# 5. Matrix still works (needs no AWS)
python3 workloads-live-repo/scripts/generate_account_matrix.py      # every entry's working_directory is <repo>/<account>; same accounts as before the change
# 6. Hygiene
python3 -m json.tool renovate.json >/dev/null && echo json-ok
git status --short                                                   # clean; no .terragrunt-cache, .terraform, provider.tf, backend.tf
git log --oneline main..HEAD                                         # 7 commits
```

## Done means

- [ ] 7 commits on `refactor/simple-terragrunt`, messages as given. Nothing pushed.
- [ ] `46 stacks compared, 0 differences` from the render compare.
- [ ] No `_envcommon`, `account.hcl`, `env.hcl`, `region.hcl`, `module_versions`, `IAC_MODULES_LOCAL` left (verify step 3).
- [ ] Both `root.hcl` identical; every leaf follows the template; the one-file check fails on a bad leaf and passes on the repo.
- [ ] All tests, `make test`, `make checkov` green.

**Report back:** commit list; the compare script's last line and any script fix you made; the output of each verify step; every
deviation with the reason; a **"not checked"** list (at least: anything that needs AWS, the Renovate config validator, the workflows on GitHub).

## Owner: state move (Karthik, by hand, after merging; the implementer never does this)

Five stacks are already applied. Their state keys change. **Move them, don't recreate them:**
- `organization`: an organization with member accounts can't be deleted and recreated.
- `account-factory`: a destroy tries to close the member accounts. Closures are rate-limited and closed accounts sit suspended for 90 days.
- `bootstrap-stacksets`: a destroy deletes the CI roles and state buckets in the member accounts.
- `budgets` / `identity-center` *could* be recreated, but moving is simpler and keeps the identity assignments stable.

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
  (cd foundation-live-repo/management/$s && terragrunt plan -out=tfplan)
done
```
**What each plan must show:** `0 to add, N to change, 0 to destroy`, where every change is `tags` / `tags_all` with `Service` going from the
old path (`management/_global/governance/organization`) to the new one (`management/_global/organization`). **Anything else** (a create, a
destroy, a changed argument): stop, don't apply, and keep the old keys. Copying was non-destructive, so nothing is lost.

If all five are clean: `terragrunt apply tfplan` in each folder. Then remove the old keys (the bucket is versioned, so they stay recoverable):
`aws s3 rm "$B/management/_global/governance/organization/terraform.tfstate"` (and the other four old keys).
Finally `aws s3 ls $B --recursive` should list exactly the five new keys.

## Out of scope

- Changing any module in `iac-modules-repo/` (except the two README path mentions) or release-please.
- Updating `policy-library-repo/terraform/require_tags.rego:7` (comment only): **owner**.
- Removing `.terragrunt-cache` handling from `.gitignore`, or the leftover old Renovate PRs on GitHub: owner's call.
- Pinning prod to release tags again: revisit only when the live repos really become separate repos.
- Digger, OpenTofu (both parked in PLAN.md 8.11 / 8.12).
- The other PR #71 review findings (janitor/CSI volumes, X-Ray permission, concurrency, gate wording): they belong to the PR #71 fix-up. Part 0 only checks the `min_size` one.
