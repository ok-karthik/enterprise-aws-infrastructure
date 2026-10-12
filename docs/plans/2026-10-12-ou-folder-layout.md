# Plan: OU folders in `iac-live-repo/`, state keys unchanged

- **Written:** 2026-10-12 by Claude Opus 5.5 (planner). **Executor:** `implementer` (Sonnet tier).
- **Branch:** `refactor/ou-folders` from `main` at `2868f0c` (PR #72 merged). Start with
  `git fetch origin && git switch main && git pull --ff-only && git switch -c refactor/ou-folders`.
- **One commit per part**, messages as given, each ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Stage files explicitly** (`git add <paths>`), never `git add -A` / `git add .`. The owner's checkout may have
  uncommitted files. Never stage, stash or revert them.
- **Do NOT:** push, open a PR, merge, use AWS credentials or the default AWS profile, run apply/destroy/import/state/force-unlock,
  or edit `.checkov.yaml`, `.trivyignore`, `.claude/`, `policy-library-repo/`, `PLAN.md`, `SIMPLIFY_PLAN.md`,
  `LEARNING_PLAN.md`, `learning/`, `docs/EXECUTION_LOG.md`, `CLAUDE.md`, or `docs/plans/`.
- `export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache` before any terraform/terragrunt/make call.

## Goal

The folders under `iac-live-repo/` show the AWS Organizations OU tree (OU → account → region → stack), so a reader
sees what is an OU and what is an account. The state key and the `Service` tag stay `<account>/<region>/<stack>`,
exactly as today. Moving an account to another OU later is a folder move plus one registry line, never a state move.

## Scope (only these files may change)

| Part | Files |
|---|---|
| 1 | `iac-live-repo/_config/organization.hcl`, `iac-live-repo/management/_global/organization/terragrunt.hcl` (still at its flat path; Part 2 moves it) |
| 2 | `iac-live-repo/root.hcl`, every stack folder (`git mv` only, no content change), `.github/CODEOWNERS`, `infracost-config.yml` |
| 3 | `scripts/check-account-registry.sh`, `scripts/generate_account_matrix.py`, `scripts/generate-module.sh`, `scripts/smoke-test.sh`, `scripts/org_tree.py` (new), `scripts/tests/test_one_file_rule.py`, `scripts/tests/test_generate_account_matrix.py`, `scripts/tests/test_plan_scope.py`, `scripts/tests/test_org_tree.py` (new), `Makefile`, `.github/actions/static-analysis/action.yml` (add the org-tree check) |
| 4 | `iac-agents-repo/iac_agent/iac_agent.py`, `iac-agents-repo/prompts/iac_agent.md`, `iac-agents-repo/tests/test_platform.py`, `iac-agents-repo/tests/test_healer_guards.py` |
| 5 | `iac-live-repo/README.md`, `AGENTS.md`, `docs/CICD.md`, `docs/ARCHITECTURE.md`, `docs/COMPLIANCE.md`, `docs/DISASTER_RECOVERY.md`, `docs/FINOPS.md`, `docs/runbooks/drill-bad-scp-rollback.md`, `docs/visualizer.html`, `iac-live-repo/_bootstrap/README.md`, `iac-modules-repo/governance/bootstrap-stacksets/README.md`, `docs/adr/0001-repository-topology.md`, `docs/migrations/2026-10-simple-layout.md` (append a section only) |

## What was measured — do not re-derive (2026-10-12, `origin/main` = `2868f0c`)

| # | Fact |
|---|---|
| M1 | `iac-live-repo/` holds 8 account folders (`management log-archive security-tooling network-hub shared-services observability workloads-dev workloads-prod`), `_config/`, `_bootstrap/`, `root.hcl`, `README.md`; 46 `terragrunt.hcl` stacks at `<account>/<region\|_global>/<stack>/`. |
| M2 | `root.hcl` derives `account_name = path_parts[0]`, `region_dir = path_parts[1]`, and uses `path_relative_to_include()` for both the state `key` and the `Service` default tag. It exposes `account_name account account_id env ou alias owner data_classification aws_region registry regions organization`. |
| M3 | Registry `ou` values: management=Root, log-archive/security-tooling=Security, network-hub/shared-services/observability=Infrastructure, workloads-dev=NonProd, workloads-prod=Prod. |
| M4 | The OU tree exists only as the default of `organizational_units` in `iac-modules-repo/governance/organization/variables.tf` (`Security, Infrastructure, Workloads, Prod{parent=Workloads}, NonProd{parent=Workloads}, Sandbox, Policy-Staging, Suspended`). The organization stack does not pass it, and `_config/organization.hcl` holds only `organization_id` and `log_archive_kms_key_arn`. |
| M5 | The only dependencies that cross folders are inside `network-hub` (`tgw-peering` → `../../eu-west-1/transit-gateway` and `../../eu-central-1/tgw-peering`). They are relative inside one account, so a `git mv` of the whole account folder keeps them valid. |
| M6 | Things that encode `iac-live-repo/<account>`: `generate_account_matrix.find_account_dir` (`root/LIVE_REPO/name`) and `expand_per_region` (glob `*/*/terragrunt.hcl` under the account dir, which still works); `check-account-registry.sh` (top-level non-`_` folder = account; leaf must be exactly 3 deep); `generate-module.sh` (`ACCOUNT_DIR="iac-live-repo/$ACCOUNT"`); `Makefile` `plan` (`cd iac-live-repo/$(ACCOUNT)`); `smoke-test.sh` default `iac-live-repo/workloads-dev`; `infracost-config.yml` paths; `.github/CODEOWNERS` comments; `iac_agent.live_env_dir` (`iac-live-repo/workloads-<env>`) and its tests. Workflows take `working_directory` from the matrix, so they need no path edit. |
| M7 | Docs that name flat paths: `AGENTS.md`, `docs/{COMPLIANCE,DISASTER_RECOVERY,FINOPS}.md`, `docs/runbooks/drill-bad-scp-rollback.md`, `docs/visualizer.html`, `iac-live-repo/_bootstrap/README.md`, `iac-modules-repo/governance/bootstrap-stacksets/README.md`, `iac-agents-repo/prompts/iac_agent.md`. History, not to edit: `docs/migrations/2026-10-simple-layout.md` (append only), `docs/plans/*`. |
| M8 | `terragrunt render --format json` works offline for all 46 stacks (deps fall back to mocks). Real ids come from the owner's gitignored `iac-live-repo/_config/accounts.local.hcl`; it must exist for the compare and stays where it is (not under an account folder, so no move). |
| M9 | The owner applied 5 stacks with keys `management/_global/{organization,account-factory,bootstrap-stacksets}` and `management/eu-central-1/{identity-center,budgets}` in `tg-state-954171757349-eu-central-1`. These keys must not change. |

## Decisions (do not reopen)

- **Target layout:** `iac-live-repo/<ou path>/<account>/<region|_global>/<stack>/terragrunt.hcl`. The OU folder is the
  OU name in lowercase. A child OU sits under its parent. Root = `root`.

  | Account | New account folder |
  |---|---|
  | management | `iac-live-repo/root/management` |
  | log-archive, security-tooling | `iac-live-repo/security/<account>` |
  | network-hub, shared-services, observability | `iac-live-repo/infrastructure/<account>` |
  | workloads-dev | `iac-live-repo/workloads/nonprod/workloads-dev` |
  | workloads-prod | `iac-live-repo/workloads/prod/workloads-prod` |

  Don't create folders for OUs that have no account with stacks (Sandbox, Policy-Staging, Suspended). `org-tree` shows them.
- **The OU tree gets one source:** `_config/organization.hcl` gains `organizational_units`, the exact value of the module
  default (M4). The organization stack passes it (`organizational_units = include.root.locals.organization.organizational_units`).
  The scripts read the OU folders from the same map, so there is one source for both.
- **root.hcl:** the account, region and stack are the last three folders, and the OU path is everything before them.
  The key and the `Service` tag are built from the last three only.
- **Verification:** a full-JSON render diff. Every field is compared, with no `.get()` defaults. The only allowed
  difference is the new input `organizational_units` on the organization stack, whose value must equal the module default.
- **check-account-registry.sh:** an account folder's OU path must equal the registry OU mapped through
  `organizational_units`.
- **CODEOWNERS:** one line per OU folder, all `@ok-karthik` for now, each with a comment naming the team that would own it in a company.

## Part 0 — Baseline (no commit)

On `main` before any change, from the repo root:
```bash
export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache
S=/private/tmp/claude-501/ou-folders; rm -rf $S; mkdir -p $S/before $S/after
test -f iac-live-repo/_config/accounts.local.hcl || { echo "STOP: owner's accounts.local.hcl missing"; exit 1; }
for f in $(find iac-live-repo -name terragrunt.hcl -not -path '*/.terragrunt-cache/*' | sort); do
  d=$(dirname "$f"); k=$(echo "${d#iac-live-repo/}" | tr '/' '_')
  (cd "$d" && env -u AWS_PROFILE AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null \
     terragrunt render --format json --non-interactive --log-format bare >"$S/before/$k.json" 2>/dev/null) || echo "RENDER FAIL $d"
done
ls $S/before/*.json | wc -l      # must be 46, and no "RENDER FAIL"
find iac-live-repo -type d -name .terragrunt-cache -prune -exec rm -rf {} +
```
Save the mapping: for each stack, `old = <account>/<region>/<stack>`. The new path is the OU folder from the table
plus `old`. Write `$S/mapping.tsv` (old-dir-relative-to-iac-live-repo, new-dir) with a short script that uses the table above.

## Part 1 — OU tree in `_config/organization.hcl`

Commit: `refactor(config): the OU tree lives in _config/organization.hcl`

1. Add the following to `iac-live-repo/_config/organization.hcl`, with this comment:
   "The OU tree. One source: the organization stack creates these OUs, and iac-live-repo's folders mirror them (lowercase; a child OU sits under its parent; Root = `root/`)."
   ```hcl
   organizational_units = {
     "Security"       = {}
     "Infrastructure" = {}
     "Workloads"      = {}
     "Prod"           = { parent = "Workloads" }
     "NonProd"        = { parent = "Workloads" }
     "Sandbox"        = {}
     "Policy-Staging" = {}
     "Suspended"      = {}
   }
   ```
2. In `iac-live-repo/management/_global/organization/terragrunt.hcl`, add this to `inputs`:
   `organizational_units = include.root.locals.organization.organizational_units`.
3. Render that one stack. `.inputs.organizational_units` must equal the module default, every other field must equal
   its baseline, and the plan must be unaffected (identical values = no change).

## Part 2 — Move the folders, and root.hcl reads the last three segments

Commit: `refactor(live)!: folders mirror the OU tree; state keys stay <account>/<region>/<stack>`

1. `git mv` each account folder to its new place from the table, creating parents with `mkdir -p`. That's 8 moves.
   Stack contents are not edited.
2. Replace the top of the `locals` block in `iac-live-repo/root.hcl`, and rewrite the header comment to describe the new
   layout and why keys exclude the OU:
   ```hcl
   locals {
     # Layout: <ou path>/<account>/<region or _global>/<stack>/terragrunt.hcl. The OU folders are for people; the last
     # three folders are what count. The state key and the Service tag use only those three, so moving an account to
     # another OU is a folder move, never a state move.
     path_parts   = split("/", path_relative_to_include())
     depth        = length(local.path_parts)
     ou_path      = join("/", slice(local.path_parts, 0, local.depth - 3))
     account_name = local.path_parts[local.depth - 3]
     region_dir   = local.path_parts[local.depth - 2]
     stack_name   = local.path_parts[local.depth - 1]
     stack_path   = "${local.account_name}/${local.region_dir}/${local.stack_name}"
   ```
   Keep the rest of the existing locals. Expose `ou_path` and `stack_path` too. Make these two replacements:
   - in the provider, `Service = "${path_relative_to_include()}"` → `Service = "${local.stack_path}"`
   - in remote_state, `key = "${path_relative_to_include()}/terraform.tfstate"` → `key = "${local.stack_path}/terraform.tfstate"`
3. `.github/CODEOWNERS`: replace the commented per-account examples with one active line per OU folder, all
   `@ok-karthik`, each with a comment naming the company owner:
   - `/iac-live-repo/root/` platform leads
   - `/iac-live-repo/security/` security team
   - `/iac-live-repo/infrastructure/` network/platform team
   - `/iac-live-repo/workloads/prod/` platform team + service owners
   - `/iac-live-repo/workloads/nonprod/` platform team

   Keep `/iac-live-repo/ @ok-karthik` as the first line.
4. `infracost-config.yml`: change the two project paths to `iac-live-repo/workloads/nonprod/workloads-dev` and
   `iac-live-repo/workloads/prod/workloads-prod`.
5. Render all 46 new paths into `$S/after/` (same loop, key = old path from the mapping), then run the compare below.
   Expect `46 compared, 1 allowed difference (organization.organizational_units), 0 other differences`.

`$S/compare.py`:
```python
import json, os, sys
S = sys.argv[1]; rows = [l.rstrip("\n").split("\t") for l in open(f"{S}/mapping.tsv") if l.strip()]
REPO = os.getcwd()
def norm(d, stack_dir):
    d = json.loads(json.dumps(d))
    for dep in (d.get("dependency") or {}).values():   # config_path is relative to the stack dir: make it the old account/region/stack form
        p = os.path.normpath(os.path.join(REPO, stack_dir, dep["config_path"]))
        dep["config_path"] = "/".join(p.split("/")[-3:])
    d.pop("locals", None)                               # root locals gain ou_path/stack_path; inputs and generated files are what matter
    return d
def walk(a, b, path, out):
    if type(a) != type(b): out.append(f"{path}: {a!r} -> {b!r}"); return
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a: out.append(f"{path}.{k}: <missing> -> {b[k]!r}")
            elif k not in b: out.append(f"{path}.{k}: {a[k]!r} -> <missing>")
            else: walk(a[k], b[k], f"{path}.{k}", out)
    elif isinstance(a, list):
        if len(a) != len(b): out.append(f"{path}: len {len(a)} -> {len(b)}"); return
        for i, (x, y) in enumerate(zip(a, b)): walk(x, y, f"{path}[{i}]", out)
    elif a != b: out.append(f"{path}: {a!r} -> {b!r}")
allowed = other = 0
for old, new in rows:
    k = old.replace("/", "_")
    a = norm(json.load(open(f"{S}/before/{k}.json")), f"iac-live-repo/{old}")
    b = norm(json.load(open(f"{S}/after/{k}.json")), new)
    diffs = []; walk(a, b, "", diffs)
    for x in diffs:
        if old == "management/_global/organization" and x.startswith(".inputs.organizational_units: <missing>"):
            allowed += 1; continue
        other += 1; print(f"DIFF {old}: {x}")
print(f"{len(rows)} compared, {allowed} allowed difference(s), {other} other differences"); sys.exit(1 if other or len(rows) != 46 else 0)
```
(`.terraform.source` contains the absolute repo path, which is unchanged. The source of module code doesn't move.)
Run it with `python3 $S/compare.py $S`. Any "other difference" means stop and fix; never relax the script.
The baseline is from before Part 1, so the Part 1 input is the one allowed difference.

## Part 3 — Scripts, `make org-tree`, tests

Commit: `feat(scripts): OU-aware layout checks and make org-tree`

1. **Shared helper.** In `scripts/generate_account_matrix.py` add `parse_ous(text) -> dict[str, str|None]` (OU → parent),
   which reads the `organizational_units` block of `_config/organization.hcl` with a regex in the style of
   `parse_registry`. Also add `ou_folder(ou, ous) -> str`: `"root"` for `Root`, else
   `"<parent lower>/<ou lower>"` when there is a parent, else `"<ou lower>"`. Then change
   `find_account_dir(root, name)` to return `root/LIVE_REPO/ou_folder(fields["ou"])/name` if that is a dir, else
   `None`. Pass the fields or the OU in, and update the call site. `expand_per_region` keeps working unchanged
   (its key stays `<account>/<region>`). Its `working_directory` is now the OU path. Assert that in a test.
2. **`check-account-registry.sh`:**
   - Walk the account folders as "any directory under `iac-live-repo/` (not `_*`, not `.terragrunt-cache`) whose name
     is a registry account".
   - For each one, its parent path relative to `iac-live-repo/` must equal `ou_folder(registry ou)`. Fail with
     `❌ <path>: account '<name>' is in OU '<ou>' (registry), so its folder must be iac-live-repo/<expected>/<name>`.
   - Any other directory directly under an OU folder that is neither a registry account nor a child OU folder also fails.
   - Each `terragrunt.hcl` must be at `<ou folder>/<account>/<region>/<stack>/terragrunt.hcl`.
   - Keep the one-file rule and the region-per-OU rules unchanged.
3. **`scripts/org_tree.py`** (stdlib only; imports `parse_registry`, `parse_ous`, `ou_folder`, `load_accounts` from
   `generate_account_matrix`). It prints this, with every OU (empty ones too) in the map order and accounts sorted:
   ```
   Root
   ├── management            954171757349      iac-live-repo/root/management
   ├── Security
   │   ├── log-archive       <id or placeholder> iac-live-repo/security/log-archive
   ...
   ├── Sandbox               (no accounts)
   ```
   - Show the real id if `accounts.local.hcl` provides it, else `placeholder`.
   - Print `(no live folder)` when the folder does not exist.
   - **IDs in the README:** the README block must not contain real ids (the repo is public). With `--readme` or
     `--check`, print `id` only as `real` or `placeholder`.
   - `--readme` rewrites the block between `<!-- org-tree:start -->` and `<!-- org-tree:end -->` in
     `iac-live-repo/README.md`.
   - `--check` exits 1 with `org tree in iac-live-repo/README.md is stale: run make org-tree` if the block differs.
4. **Makefile:**
   - `org-tree: ## Print the OU tree (and refresh iac-live-repo/README.md)` → `python3 scripts/org_tree.py && python3 scripts/org_tree.py --readme`.
   - `plan`: resolve the folder by account name:
     ```make
     cd "$$(python3 -c 'import sys; sys.path.insert(0,"scripts"); import generate_account_matrix as g; from pathlib import Path; d=g.find_account_dir(Path("."), sys.argv[1], None); print(d or sys.exit("unknown account: "+sys.argv[1]))' $(ACCOUNT))" && terragrunt run --all plan ...
     ```
     A cleaner equivalent is fine: add a `--dir NAME` flag to `generate_account_matrix.py` that prints the folder or
     exits 2, and use that.
5. `scripts/generate-module.sh`: set `ACCOUNT_DIR` from that same `--dir` lookup instead of `iac-live-repo/$ACCOUNT`.
6. `scripts/smoke-test.sh`: change the default `ACCOUNT_DIR` to `iac-live-repo/workloads/nonprod/workloads-dev`, and the usage comment.
7. `.github/actions/static-analysis/action.yml`: add a step `python3 scripts/org_tree.py --check` next to the
   existing check-account-registry step.
8. **Tests:**
   - `test_one_file_rule.py`:
     - an account in the wrong OU folder fails
     - a nested OU (`workloads/nonprod/<acct>`) passes
     - `root/management` passes
     - a stray folder under an OU fails
   - `test_generate_account_matrix.py`: `working_directory` is the OU path; per-region keys are unchanged.
   - `test_org_tree.py`:
     - the tree text for a synthetic registry with an empty OU
     - `--check` passes when fresh and fails when stale
     - the README block never contains a 12-digit id
   - `test_plan_scope.py`: path strings only, if any break.

## Part 4 — IaC agent

Commit: `refactor(iac-agent): find account folders through the OU layout`

`iac_agent.live_env_dir(env, root)` returns the account folder found through `generate_account_matrix.find_account_dir`
for `workloads-<env>`. If not found, it returns the expected OU path (`ou_folder` of the registry entry). Update
`prompts/iac_agent.md` (layout lines) and the tests (`test_platform.py` expected paths, `test_healer_guards.py` OK_PATHS
→ `iac-live-repo/workloads/nonprod/workloads-dev/eu-central-1/vpc/terragrunt.hcl`).

## Part 5 — Docs

Commit: `docs: OU folders in iac-live-repo; keys stay account/region/stack`

- **`iac-live-repo/README.md`:**
  - New "How it is laid out" tree with OU folders.
  - The `<!-- org-tree -->` block (filled by `make org-tree`).
  - "Move an account to another OU" as 3 steps:
    1. Change `ou` in `_config/accounts.hcl` (the organization/account-factory stack moves it in AWS on apply).
    2. `git mv` the account folder to the new OU folder.
    3. `scripts/check-account-registry.sh` and `make org-tree`. **No state move:** keys are account/region/stack.
- **`AGENTS.md`:** update §1 (layout line) and §4 the same way, then fix the flat paths everywhere else in it.
- **Other docs:** update the flat paths in `docs/CICD.md`, `docs/ARCHITECTURE.md` and the M7 docs (path text only).
- **`docs/adr/0001-repository-topology.md`:** append a "Revision 2026-10-12 (DRAFT by the model; owner to rewrite)"
  section. It should say: folders mirror the OU tree for people; state keys are `<account>/<region>/<stack>`, so a
  reorganisation is a folder move, not a state migration; the OU tree has one source (`_config/organization.hcl`).
- **`docs/migrations/2026-10-simple-layout.md`:** append a section "2026-10-12: OU folders, keys unchanged". It holds
  the folder table above and the line "No state moves. After merge, `terragrunt plan` in the 5 applied stacks shows No changes."

## Rules this task can break

1. Never edit `.checkov.yaml`, `.trivyignore`, `.claude/`, `policy-library-repo/`. Accept a Checkov finding only inline with a reason.
2. Offline only: no AWS credentials, no default profile, no apply/destroy/import/state/force-unlock. Render with the `env -u AWS_PROFILE ...` prefix.
3. After an edit inside a module run `make verify-module`. Stop after 3 failed runs in a row on one module. (No module code changes are planned.)
4. The state key and the `Service` tag must not change for any stack: the compare proves it, and nothing relaxes the compare.
5. Never invent account ids. Real ids stay out of tracked files (the org-tree README block shows only `real`/`placeholder`).
6. Stage explicitly. Remove every `.terragrunt-cache` you create.

## Verify sequence (end of Part 5; look at the output)

```bash
export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache
S=/private/tmp/claude-501/ou-folders
python3 $S/compare.py $S                                   # "46 compared, 1 allowed difference(s), 0 other differences"
find iac-live-repo -name terragrunt.hcl -not -path '*/.terragrunt-cache/*' | wc -l          # 46
ls -d iac-live-repo/{management,log-archive,security-tooling,network-hub,shared-services,observability,workloads-dev,workloads-prod} 2>&1 | grep -c "No such"   # 8
terraform fmt -check -recursive iac-modules-repo iac-live-repo policy-library-repo && terragrunt hcl fmt --check
scripts/check-account-registry.sh                         # ✅ line
python3 scripts/org_tree.py                               # full tree incl. Sandbox / Policy-Staging / Suspended "(no accounts)"
python3 scripts/org_tree.py --check                       # exit 0
grep -cE '[0-9]{12}' iac-live-repo/README.md              # 0 inside the org-tree block (check the block by eye too)
python3 -m unittest discover -s scripts/tests -v 2>&1 | tail -5
python3 -m unittest discover -s iac-agents-repo/tests 2>&1 | tail -3
python3 -m unittest discover -s iac-live-repo/_bootstrap/tests 2>&1 | tail -3
make test && make checkov
make plan 2>&1 | head -1                                  # usage line, exit 2
make -n plan ACCOUNT=workloads-dev                        # cd iac-live-repo/workloads/nonprod/workloads-dev ...
python3 scripts/generate_account_matrix.py --per-region   # (empty with the owner's ci=false is fine; the tests cover the shape)
grep -rnE 'iac-live-repo/(management|log-archive|security-tooling|network-hub|shared-services|observability|workloads-dev|workloads-prod)/' \
  --exclude-dir=.git --exclude-dir=.terragrunt-cache --exclude-dir=.terraform --exclude-dir=plans --exclude-dir=learning \
  --exclude=PLAN.md --exclude=SIMPLIFY_PLAN.md --exclude=LEARNING_PLAN.md --exclude=EXECUTION_LOG.md . \
  | grep -v 'docs/migrations/2026-10-simple-layout.md' | grep -v 'docs/adr/'    # empty
find iac-live-repo -type d -name .terragrunt-cache | wc -l   # 0
git status --short                                         # only the owner's own uncommitted files, if any
git log --oneline main..HEAD                               # 5 commits
```

## Done means

- [ ] 5 commits on `refactor/ou-folders`, nothing pushed.
- [ ] The compare shows 0 other differences: every stack's state key, `Service` tag, inputs, generated files and dependencies are unchanged, apart from the one allowed organization input.
- [ ] The folders match the OU table; `check-account-registry.sh` enforces OU == registry.
- [ ] `make org-tree` prints the full tree incl. empty OUs; the README block is generated, checked in CI, and has no real ids.
- [ ] Every test suite, `make test` and `make checkov` pass; the stale-path grep is empty.

**Report back:** the commits, each verify command with its key output line, every deviation with its reason, and a
"not checked" list (at least: CI on GitHub, real plans after merge).

## Owner section (after merge)

- **No state moves.** The keys are unchanged by design (the compare proves it).
- Run `terragrunt plan` in the 5 applied stacks at their new folders:
  - `iac-live-repo/root/management/_global/{organization,account-factory,bootstrap-stacksets}`
  - `iac-live-repo/root/management/eu-central-1/{identity-center,budgets}`

  Expect **"No changes"**. For organization, the explicit `organizational_units` equals what was applied.
- The 8 OUs in AWS stay as they are. They are managed by the organization stack: never delete or rename them in the
  console. To change the tree, edit `_config/organization.hcl` and apply the organization stack.
- Rewrite the ADR 0001 revision in your own words.

## Out of scope

- Creating folders for empty OUs (Sandbox, Policy-Staging, Suspended): `org-tree` shows them.
- Changing any module, the OU tree itself, or applying anything.
- CODEOWNERS with real team handles (only comments name the teams).
