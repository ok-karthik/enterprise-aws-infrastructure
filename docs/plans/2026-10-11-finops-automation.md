# Plan: FinOps automation — prevent, detect, fix (PLAN 9.5)

- **Written:** 2026-10-11 by Claude Opus 5.5 (planner). **Executor:** the `implementer` agent (Sonnet tier).
- **Branch:** `feat/p9-5-finops-automation` from `main` (`13b25c5` at writing time).
- **One commit per part**, conventional-commit messages as given in each part (release-please reads them).
- **Do NOT:** push, open a PR, merge, publish, run `apply`/`destroy`/`import`, use any AWS credentials or the
  shell's default AWS profile, or edit `.checkov.yaml`, `.trivyignore`, `policy-library-repo/`, `.claude/`.
  Everything here is validated **offline**. If a step seems to need AWS, stop and write it under "not checked".
- Always `export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache` before any `terraform`/`make` call
  (mobile data: the AWS provider must not be downloaded again).

## Goal (one paragraph)

Today cost is only *visible* (Infracost PR comment, budgets, anomaly detection, CUR export). This task makes it
*act*: a PR that raises cost too much fails unless someone approves it with a label; a weekly job posts the top cost
movers and savings recommendations as a GitHub Issue; the dev EKS nodes switch off at night; and a janitor
Lambda reports (and, only when switched on, removes) orphaned resources in dev. It also removes three claims in
`docs/FINOPS.md` that the code does not back up.

## Scope — the only files that may change

| Part | Files |
|---|---|
| 1 | `docs/FINOPS.md`, `AGENTS.md` (the one Infracost bullet in §5) |
| 2 | `workloads-live-repo/scripts/cost_gate.py` (new), `workloads-live-repo/scripts/tests/test_cost_gate.py` (new), `workloads-live-repo/scripts/tests/fixtures/infracost_*.json` (new), `.github/workflows/reusable-terragrunt.yml` (cost-analysis job only) |
| 3 | `iac-modules-repo/governance/billing/{main.tf,variables.tf,outputs.tf,README.md,tests/billing.tftest.hcl}`, `iac-modules-repo/governance/organization/variables.tf` (the `aws_service_access_principals` default only) |
| 4 | `workloads-live-repo/scripts/cost_report.py` (new), `workloads-live-repo/scripts/tests/test_cost_report.py` (new), `.github/workflows/finops-weekly.yml` (new) |
| 5 | `iac-modules-repo/compute/eks/{main.tf,variables.tf,outputs.tf,README.md,tests/*.tftest.hcl}`, `workloads-live-repo/workloads/nonprod/workloads-dev/env.hcl`, `workloads-live-repo/_envcommon/compute/eks.hcl` |
| 6 | `iac-modules-repo/governance/cost-janitor/**` (new module), `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/cost-janitor/terragrunt.hcl` (new), `workloads-live-repo/workloads/nonprod/workloads-dev/env.hcl` (`module_versions` line only), `release-please-config.json`, `.release-please-manifest.json`, `Makefile` (`docs` target, one line), `AGENTS.md` (§2 module table, one row) |
| 7 | `docs/FINOPS.md`, `docs/CICD.md` |

Anything else is out of bounds. `PLAN.md` and `docs/EXECUTION_LOG.md` are local-only owner files: don't touch them.

## What was measured — do not re-derive (2026-10-11, this checkout at `13b25c5`)

| # | Fact | How it was checked |
|---|---|---|
| M1 | `docs/FINOPS.md` claims (a) "any change increasing monthly costs by more than 20% requires explicit Senior Engineer review", (b) "S3 Intelligent-Tiering automatically enabled for data buckets", (c) "EBS snapshots older than 30 days are automatically transitioned to Glacier or deleted". **None exist in code.** `AGENTS.md` §5 also says Infracost "blocks agent changes exceeding configured budget thresholds": false, the job only posts a comment. | grep of all `.tf`/`.hcl`/workflows for `intelligent`, `dlm`, threshold logic: 0 hits |
| M2 | `security/log-archive` already has lifecycle `archive-then-expire`: GLACIER after `glacier_transition_days` (≥ 30), expire after retention. Intelligent-Tiering is the wrong tool for logs (access pattern is known: write once, rarely read). | `iac-modules-repo/security/log-archive/main.tf:319-350` |
| M3 | The cost job is `cost-analysis` in `.github/workflows/reusable-terragrunt.yml` (≈ lines 191-290). It runs `infracost breakdown --path <plan.json> --format json` per plan into `cost-*.json`, then `infracost output ... --format table`, writes `/tmp/pr-comment.md`, and the "Post PR Comment" step (github-script) creates/updates one comment per account, found by the text `Infrastructure Change Summary (<account>)`. Infracost CLI `0.10.44`. It runs per account (one job per account), on PRs **and** on push to `main`. | read the file |
| M4 | Infracost combined JSON (`infracost output --format json`) has top-level `totalMonthlyCost`, `pastTotalMonthlyCost`, `diffTotalMonthlyCost` (strings like `"123.45"`, or `null` when nothing is priced) and a `projects[]` list with the same fields under `breakdown`/`pastBreakdown`/`diff`. **Infracost is not installed locally**, so the first real file is seen on the first CI run: the parser must accept strings, numbers and `null`. | Infracost JSON schema 0.2; `command -v infracost` → none |
| M5 | A label added to a PR does **not** re-run CI (`pull_request` default types are opened/synchronize/reopened), and "Re-run failed jobs" reuses the **original event payload**, so `github.event.pull_request.labels` is stale. Labels must be read live through the API at run time. | GitHub Actions behaviour |
| M6 | The plan role (`github-actions-plan`, in every account incl. management) has AWS managed `ReadOnlyAccess`, which includes `ce:GetCostAndUsage`, `ce:ListCostAllocationTags`, `cost-optimization-hub:ListRecommendations`, `cost-optimization-hub:ListEnrollmentStatuses`, `compute-optimizer:Get*`. **No IAM change is needed** for the weekly report. | `account-bootstrap.yaml` PlanRole → `arn:aws:iam::aws:policy/ReadOnlyAccess`; AWS managed policy reference page, fetched 2026-10-11 |
| M7 | Each Cost Explorer API request costs $0.01. The weekly report makes ≤ 6 calls → < $0.30/month. | AWS pricing |
| M8 | `generate_account_matrix.py --account management --github-output` prints one JSON entry and writes `plan_role_arn`, `account_id`, ... to `$GITHUB_OUTPUT`; it **exits non-zero** if management is not in the matrix (placeholder id / `ci = false`). It reads real ids from env `ACCOUNTS_LOCAL_HCL` (pattern: `drift-detection.yml` matrix job). | `generate_account_matrix.py:186-193, 91-98` |
| M9 | Toolchain image (`ghcr.io/ok-karthik/infrastructure-toolchain:latest`) has `python3`, `pip`, `jq`, AWS CLI v2, and Checkov (which depends on boto3). boto3 importability in the image was **not** run; the workflow checks it (Part 4). | `.github/docker/Dockerfile:74-95` |
| M10 | AWS provider `6.66.0` (locked in billing) has `aws_costoptimizationhub_enrollment_status`, `aws_computeoptimizer_enrollment_status`, `aws_scheduler_schedule`. Billing already declares `configuration_aliases = [aws.us_east_1]`; Cost Optimization Hub's API is us-east-1 only. | `grep -a` on the cached provider binary |
| M11 | Enrolling Cost Optimization Hub from the management account turns on Organizations trusted access for `cost-optimization-hub.bcm.amazonaws.com` itself. The `governance/organization` variable `aws_service_access_principals` is **AUTHORITATIVE** (its description: "any principal enabled by hand and missing here is disabled on apply"). So both `cost-optimization-hub.bcm.amazonaws.com` and `compute-optimizer.amazonaws.com` must be added there, or the next org apply silently turns them off. | AWS docs "Cost Optimization Hub and AWS Organizations trusted access"; `organization/variables.tf:36-62` |
| M12 | EKS module: node group `spot_nodes` uses `ami_type = "AL2023_x86_64_STANDARD"` but `instance_types` default is `["t4g.small", "t4g.medium"]` (Graviton/ARM), and `_envcommon/compute/eks.hcl` does not override `instance_types`. **x86 AMI on ARM instances cannot launch: this is a real bug** in every env. Nothing has been applied, so changing `ami_type` costs nothing. | `compute/eks/main.tf:30-36`, `variables.tf:40-44`, `_envcommon/compute/eks.hcl` |
| M13 | Upstream `terraform-aws-modules/eks` `21.19.0` node group has `lifecycle { ignore_changes = [scaling_config[0].desired_size] }`. So a schedule that changes **desired size only** causes no drift. Changing min size would. The node group name has a random suffix (`use_name_prefix` default true); the submodule output `node_group_id` is `"<cluster>:<nodegroup>"`. No Karpenter controller is installed (only its AWS prerequisites), so the node group is the only capacity. | `.terraform/modules/eks/modules/eks-managed-node-group/main.tf:554-557`, `outputs.tf:34-37`; grep for `helm_release`: 0 hits |
| M14 | Dev `env.hcl`: `min_size = 1`, `desired_size = 1`, `single_nat_gateway = true`. Desired size can't go to 0 while min size is 1, so dev min must become 0. | `workloads-dev/env.hcl` |
| M15 | Checkov `CKV_AWS_66` (log group must set retention) is **not** skipped in `.checkov.yaml`, so "no log group without retention" is already enforced for code we write. The janitor's log-retention fix is only for log groups created outside Terraform (for example by Lambda or EKS add-ons). | `.checkov.yaml` skip list |
| M16 | Single-account configs are now inlined in the leaf `terragrunt.hcl`, not put in `_envcommon` (commit `13b25c5`). Configs shared by many accounts stay in `_envcommon`. | `git show --stat 13b25c5` |
| M17 | Lambda module pattern to copy: `iac-modules-repo/security/auto-remediation` (`src/*.py`, `archive_file` into `.build/`, log group with `retention_in_days`, inline `#checkov:skip` with reasons on `aws_lambda_function`, `tests/test_*.py` importing `from src.<file> import ...` with hand-written fake clients, no boto3/moto in tests). `make test` runs `tests/test_*.py` per module. | read the module + `Makefile:58-68` |
| M18 | CI runs `python3 -m unittest discover -s workloads-live-repo/scripts/tests` in the static-analysis action. New script tests placed there run in CI automatically. | `.github/actions/static-analysis/action.yml:49` |
| M19 | **Baseline `make verify-module` results before any change:** `compute/eks` ok, `governance/organization` ok, `governance/billing` **FAILED: validate** ("Provider configuration not present ... us_east_1"). That failure is the known Terraform limitation for modules with `configuration_aliases`; its `test` step passes. **Don't try to fix it.** For billing, "green" means init/tflint/checkov/test PASS and validate fails with that same message only. | ran all three, 2026-10-11 |
| M20 | Weekday working hours 07:00-19:00 = 60 h of 168 h per week, so night + weekend shutdown removes **64 %** of node hours. The EKS control plane (~$0.10/h ≈ $73/month) keeps running and is not reduced. | arithmetic |

## Decisions already made (do not reopen)

- **Threshold:** fail when the monthly diff is ≥ **$100**, or when it is ≥ **$10** *and* ≥ **20 %** of the past cost.
  The $10 floor stops "+$1 on a $4 sandbox" from failing every PR. Values come from workflow env vars with these defaults.
- **Override:** a PR label `cost-approved`, read live from the API (M5). The gate runs only on pull requests, never on push to `main`.
- **Intelligent-Tiering is dropped**, not built (M2). FINOPS.md describes the real Glacier lifecycle instead.
- **Log-retention policy:** Checkov already covers it (M15). **No Rego in this task.** Rego for `gp2` is an owner follow-up (see Out of scope).
- **Night shutdown lives inside the `compute/eks` module** (optional variable, off by default), because it needs the
  node group name, which only that module knows (M13). It changes desired size only.
- **Janitor is report-only by default** (`dry_run = true`), applied to **dev only**, with a `keep=true` tag opt-out enforced
  in the code *and* in the IAM policy.
- **Weekly report:** one GitHub Issue per ISO week, label `finops-weekly`. The Python script only writes Markdown;
  github-script manages the Issue (same split as `drift-detection.yml`).

---

## Part 1 — Make FINOPS.md true (docs)

Commit: `docs(finops): remove claims the code does not back (PLAN 9.5)`

1. `docs/FINOPS.md`:
   - "Threshold Alerts" bullet: replace with "*Planned in PLAN 9.5 Part 2*: PRs above the threshold fail unless
     labelled `cost-approved`." (Part 7 rewrites it once built.)
   - "### 3. Storage Optimization": delete the Intelligent-Tiering bullet. Replace the EBS bullet with the true
     state: "Log buckets in `security/log-archive` move to Glacier after `glacier_transition_days` and expire after
     their retention (Object Lock COMPLIANCE). Old EBS snapshots in dev are reported by the cost janitor (PLAN 9.5)."
   - "Graceful Termination: Handled via the AWS Node Termination Handler": the module sets
     `enable_spot_termination = true` on the **Karpenter** module (an SQS queue + EventBridge rules), not the Node
     Termination Handler. Reword to "Spot interruption events go to Karpenter's SQS queue (`enable_spot_termination`);
     the Karpenter controller itself is not installed yet."
   - "Future Roadmap" → delete "Automated Shutdown at Night" (Part 5 builds it; Part 7 documents it).
2. `AGENTS.md` §5 Infracost bullet: "posts a per-module cost breakdown PR comment" and, after Part 2, "and fails a PR
   whose monthly cost rises ≥ $100, or ≥ $10 and ≥ 20 %, unless it has the `cost-approved` label". Write the final
   wording now; Part 2 lands in the same branch.

Test: none (docs). Check: `grep -n "Intelligent-Tiering\|Senior Engineer\|Node Termination Handler" docs/FINOPS.md` → no output.

## Part 2 — Cost gate on PRs

Commit: `feat(ci): fail PRs whose cost rise passes the threshold unless cost-approved (PLAN 9.5)`

### 2a. `workloads-live-repo/scripts/cost_gate.py`

Python 3, standard library only. Style: like `plan_scope.py` / `merge_sarif.py` (module docstring that says what and why, `argparse`, `main() -> int`).

```
usage: cost_gate.py INFRACOST_JSON [--labels "a,b"] [--max-usd 100] [--min-usd 10] [--max-pct 20]
                    [--approve-label cost-approved] [--markdown-out FILE]
```

- `to_float(v)`: `None`/`""` → `0.0`; `str`/`int`/`float` → `float`. Anything else → `ValueError`.
- `evaluate(data, max_usd, min_usd, max_pct) -> Verdict` (dataclass: `past`, `total`, `diff`, `pct` (`None` when past == 0), `breached: bool`, `reason: str`).
  - Use top-level `pastTotalMonthlyCost`, `totalMonthlyCost`, `diffTotalMonthlyCost`. If `diffTotalMonthlyCost`
    is missing, diff = total − past.
  - `breached = diff >= max_usd or (diff >= min_usd and past > 0 and diff / past * 100 >= max_pct)`.
    **Edge:** past == 0 and diff ≥ max_usd → breached (a new $150 stack). past == 0 and diff < max_usd → not breached
    (percent is meaningless). A cost **decrease** never breaches.
- `top_projects(data, n=5)`: projects sorted by their diff, descending, as `(name, diff)`. Used in the message.
- Markdown written to `--markdown-out` (append mode, it goes under the existing PR comment):
  `### 💸 Cost gate: ✅ pass | ⚠️ over threshold, approved by label | ❌ over threshold`, one line
  `Monthly: $past → $total (+$diff, +pct%)`, the rule, and the top 5 projects. Money with 2 decimals.
- Exit codes: `0` pass or approved, `1` breached and not approved, `2` bad input (file missing, not JSON, `ValueError`).
  Print the one-line verdict to stdout either way.

### 2b. Tests `workloads-live-repo/scripts/tests/test_cost_gate.py` + fixtures

Fixtures in `workloads-live-repo/scripts/tests/fixtures/` (create the folder): `infracost_increase_large.json`
(past "50.00", total "200.00"), `infracost_increase_pct.json` (past "40.00", total "55.00": +$15, +37.5 %),
`infracost_small_sandbox.json` (past "4.00", total "6.00": +$2, +50 %, under the floor), `infracost_null.json` (all three `null`, `projects: []`),
`infracost_decrease.json` (past "300", total "100"). Each fixture has 2 projects with `name` and the three cost fields so `top_projects` is tested.

Test cases (one `test_` each): large increase breaches; percent rule breaches; small sandbox passes (floor);
null passes with diff 0; decrease passes; new stack past 0 / +$150 breaches; new stack past 0 / +$50 passes;
numbers given as JSON numbers (not strings) work; label `cost-approved` turns a breach into exit 0 with the
"approved by label" line; a different label does not; missing file → exit 2; markdown file is **appended to**, not overwritten
(write "existing\n" first, assert it is still there).

### 2c. Wire it into `reusable-terragrunt.yml` job `cost-analysis`

Add **after** "Generate FinOps Summary" and **before** "Post PR Comment":

1. Step `Combine Infracost JSON`: `infracost output --path "cost-*.json" --format json --out-file /tmp/infracost-combined.json`.
2. Step `Read PR labels (live)`, `id: labels`, `if: github.event_name == 'pull_request'`, `actions/github-script@v9`:
   `github.rest.issues.listLabelsOnIssue({owner, repo, issue_number: context.issue.number})` → `core.setOutput('names', names.join(','))`.
3. Step `Cost gate`, `id: gate`, `if: github.event_name == 'pull_request'`, `continue-on-error: true`, with env
   `COST_GATE_MAX_USD: '100'`, `COST_GATE_MIN_USD: '10'`, `COST_GATE_MAX_PCT: '20'`:
   `python3 workloads-live-repo/scripts/cost_gate.py /tmp/infracost-combined.json --labels "${{ steps.labels.outputs.names }}" --max-usd "$COST_GATE_MAX_USD" --min-usd "$COST_GATE_MIN_USD" --max-pct "$COST_GATE_MAX_PCT" --markdown-out /tmp/pr-comment.md`
   (`continue-on-error` so the comment is still posted.)
4. Leave "Post PR Comment" as it is.
5. New **last** step `Enforce cost gate`, `if: github.event_name == 'pull_request' && steps.gate.outcome == 'failure'`:
   `echo "::error title=Cost gate::Monthly cost rise is over the threshold. Add the 'cost-approved' label and re-run this job." && exit 1`.

Edge: "Post PR Comment" today has `if: github.event.pull_request.number != null || github.event_name == 'pull_request'`.
Don't change it.

## Part 3 — Turn on Cost Optimization Hub and Compute Optimizer (billing module)

Commit: `feat(billing): enroll the organization in Cost Optimization Hub and Compute Optimizer (PLAN 9.5)`

1. `governance/billing/variables.tf`: `enable_cost_optimization_hub` (bool, default `true`) and `enable_compute_optimizer`
   (bool, default `true`), each with a description saying it's free and org-wide (`include_member_accounts`).
2. `main.tf`, new section after the anomaly monitors, header comment in the module's style:
   ```hcl
   resource "aws_computeoptimizer_enrollment_status" "this" {
     count                   = var.enable_compute_optimizer ? 1 : 0
     status                  = "Active"
     include_member_accounts = true
   }

   resource "aws_costoptimizationhub_enrollment_status" "this" {
     count                   = var.enable_cost_optimization_hub ? 1 : 0
     provider                = aws.us_east_1
     include_member_accounts = true
     depends_on              = [aws_computeoptimizer_enrollment_status.this]
   }
   ```
   Comment: Cost Optimization Hub's API is us-east-1 only; it reads rightsizing data from Compute Optimizer, hence the order.
   Check the exact argument names against the provider docs for 6.66 in `.terraform/providers/...` schema
   (`terraform providers schema -json | jq '.provider_schemas[].resource_schemas["aws_costoptimizationhub_enrollment_status"]'`
   from the module dir after `init`). If an argument differs, use the schema's name and say so in the report.
3. `outputs.tf`: `cost_optimization_hub_enrolled` (bool) and `compute_optimizer_enrolled` (bool).
4. `tests/billing.tftest.hcl`: one new `run` (plan, same `providers` block as the others): both resources exist with
   `include_member_accounts == true` by default. A second `run` with both flags `false`: `length(...) == 0`.
5. `governance/organization/variables.tf`: append to the `aws_service_access_principals` default, same comment style:
   `"compute-optimizer.amazonaws.com",              # 9.5 (Compute Optimizer, org-wide)` and
   `"cost-optimization-hub.bcm.amazonaws.com",      # 9.5 (Cost Optimization Hub enables this itself; listed so the org apply does not turn it off)`.
   Keep `terraform fmt` alignment.
6. `README.md` of billing: a short "Cost Optimization Hub and Compute Optimizer" section (what, free, us-east-1, M11
   warning about the authoritative org list), then `terraform-docs markdown table --output-file README.md --output-mode inject .` if terraform-docs is installed; if not, say so in the report.

Verify: `make verify-module MODULE=governance/billing` → same as baseline M19 (validate fails with the same alias message only, `test` PASS with the new runs). `make verify-module MODULE=governance/organization` → ok.

## Part 4 — Weekly cost report

Commit: `feat(finops): weekly cost report issue from Cost Explorer and Cost Optimization Hub (PLAN 9.5)`

### 4a. `workloads-live-repo/scripts/cost_report.py`

boto3 is imported **inside `main()` only**, so the tests run without boto3. All AWS-facing functions take a client argument (M17 pattern).

- `week_windows(today: date) -> (cur_start, cur_end, prev_start, prev_end)`: current window = the 7 full days ending
  **yesterday** (`End` is exclusive in Cost Explorer, so `cur_end = today`); previous = the 7 days before. Dates as `YYYY-MM-DD`.
- `cost_by(ce, start, end, group_key, group_type) -> dict[str, float]`: one `get_cost_and_usage` call,
  `Granularity="DAILY"`, `Metrics=["UnblendedCost"]`, `GroupBy=[{"Type": group_type, "Key": group_key}]`, summed over days.
  Follow `NextPageToken`. Called for `SERVICE` and `LINKED_ACCOUNT` (both windows) and `TAG`/`CostCenter` (current window only):
  6 calls in total (M7).
- `untagged_share(tag_costs) -> float`: Cost Explorer returns tag keys as `"CostCenter$<value>"`; untagged is `"CostCenter$"`. Share = untagged / total × 100. Total 0 → 0.
- `costcenter_active(ce) -> bool`: `list_cost_allocation_tags(TagKeys=["CostCenter"])`, `Status == "Active"`. If not
  active, the report says "CostCenter is not activated as a cost allocation tag yet, so all spend shows as untagged
  (see the billing leaf's step 2)" instead of a misleading 100 %.
- `top_movers(cur, prev, n=5)`: by absolute change, with `+$x (+y %)`; a key only in `cur` is "new".
- `savings(coh, n=5)`: `list_recommendations` (us-east-1 client), follow `nextToken`, sort by
  `estimatedMonthlySavings` desc, keep `accountId`, `resourceType`, `actionType`, `resourceId`, `estimatedMonthlySavings`.
  On `botocore.exceptions.ClientError` → return the error code; the Markdown shows "Cost Optimization Hub: not
  available (`<code>`). It is enabled by `governance/billing` (PLAN 9.5 Part 3) once that is applied." Catch it by
  checking `hasattr(e, "response")` so the tests don't need botocore.
- `render(...) -> str` Markdown: title line, window dates, total this week vs last week, top 5 services, top 5 accounts,
  untagged share (or the not-activated note), top 5 savings with a total, and a footer: "Generated by
  `.github/workflows/finops-weekly.yml` (PLAN 9.5). Cost Explorer API cost for this report: about $0.06."
- CLI: `cost_report.py --out FILE [--today YYYY-MM-DD]`. Exit 0 on success, 1 on any AWS error other than the COH case.

### 4b. Tests `workloads-live-repo/scripts/tests/test_cost_report.py`

Fake `ce` and `coh` classes (no boto3). Cases: windows for `today=2026-10-12` (Mon) are `2026-10-05..2026-10-12` and
`2026-09-28..2026-10-05`; pagination is followed (fake returns a `NextPageToken` once); untagged share with
`CostCenter$` + `CostCenter$team-a`; not-activated note replaces the percentage; top movers order incl. a "new" key and
a decrease; savings sorted and capped at 5; COH error path gives the "not available" line and exit code 0;
`render` output contains every section header (assert on headers, not the whole text).

### 4c. `.github/workflows/finops-weekly.yml`

- `name: 'FinOps Weekly Report'`, `on: schedule: cron '0 7 * * 1'` (Mondays 07:00 UTC) + `workflow_dispatch`.
- `permissions: id-token: write, contents: read, issues: write`. `timeout-minutes: 10`.
- One job, `runs-on: ubuntu-latest`, container = the toolchain image, same `credentials` block and
  `options: --user root` as `drift-detection.yml`.
- Steps:
  1. Checkout (`actions/checkout@v6`).
  2. `Find the management account`, `id: mgmt`, env `ACCOUNTS_LOCAL_HCL: ${{ vars.ACCOUNTS_LOCAL_HCL }}`:
     ```bash
     if python3 workloads-live-repo/scripts/generate_account_matrix.py --account management --github-output; then
       echo "skip=false" >> "$GITHUB_OUTPUT"
     else
       echo "::notice title=FinOps report skipped::management is not in the CI matrix yet (placeholder id or ci = false)"
       echo "skip=true" >> "$GITHUB_OUTPUT"
     fi
     ```
  3. `Setup Platform` (`./.github/actions/setup-platform`), `if: steps.mgmt.outputs.skip == 'false'`,
     `aws_region: us-east-1`, `aws_role_arn: ${{ steps.mgmt.outputs.plan_role_arn }}`. Read-only role (M6).
  4. `Check boto3` (`python3 -c "import boto3"`); if it fails, `pip3 install --break-system-packages boto3`.
  5. `Build report`: `python3 workloads-live-repo/scripts/cost_report.py --out /tmp/cost-report.md`.
  6. `Open or update the weekly issue` (`actions/github-script@v9`): title `💰 Weekly cost report: <ISO year>-W<ww>`
     (compute the ISO week in JS). List open issues with label `finops-weekly`. **Re-run safety:** if an open issue
     with this exact title exists, `issues.update` its body (don't create a second one). Otherwise create it with
     labels `['finops-weekly']`, then close every other open `finops-weekly` issue with a comment
     "Superseded by #<new>". If the label doesn't exist, `issues.create` with the label creates it. That's fine.
- Checkov scans `.github` (it's in `.checkov.yaml` `directory`). Run `make checkov` and fix any `CKV_GHA_*` finding
  in the workflow itself. Don't add skips to `.checkov.yaml`.

## Part 5 — EKS: fix the ARM AMI and switch dev nodes off at night

Commit: `feat(eks): Graviton AMI type and optional night scale-down schedule (PLAN 9.5)`
(A `feat` because it adds a variable. Mention the AMI fix in the body: it's the bug from M12.)

1. `variables.tf`: `ami_type` (string, default `"AL2023_ARM_64_STANDARD"`) with a validation: if any entry in
   `var.instance_types` matches `^[a-z]+[0-9]+g[a-z]*\.` (Graviton: t4g, m7g, c7gn, r8g...) then `ami_type` must contain `ARM_64`,
   and if none match, it must not. Error message names both values. This needs a cross-variable validation (Terraform ≥ 1.9, already required).
2. `main.tf`: `ami_type = var.ami_type` in `spot_nodes`.
3. `variables.tf`: `scale_schedule`:
   ```hcl
   variable "scale_schedule" {
     description = "Optional working-hours schedule for the node group (dev). Sets DESIRED size only (upstream ignores desired_size drift), so min_size must be 0. null = always on."
     type = object({
       timezone     = optional(string, "Europe/Berlin")
       down_cron    = optional(string, "cron(0 19 ? * MON-FRI *)")
       up_cron      = optional(string, "cron(0 7 ? * MON-FRI *)")
       up_desired   = optional(number, 1)
     })
     default = null
   }
   ```
   Validation (cross-variable): `var.scale_schedule == null || var.min_size == 0`, message "scale_schedule needs min_size = 0, or the scale-down can't go below min".
4. `main.tf`, new section "Working-hours schedule (PLAN 9.5)", all `count = var.scale_schedule == null ? 0 : 1`:
   - `locals { node_group_name = split(":", module.eks.eks_managed_node_groups["spot_nodes"].node_group_id)[1] }`. Use `try(..., "")` so plan works with mocks.
   - `aws_iam_role` `scheduler` trusted by `scheduler.amazonaws.com` with condition `aws:SourceAccount` = current account (`data "aws_caller_identity"`; add it if the module has none).
   - `aws_iam_role_policy`: `eks:UpdateNodegroupConfig` on the node group ARN only (`module.eks.eks_managed_node_groups["spot_nodes"].node_group_arn`).
   - Two `aws_scheduler_schedule` (`down`, `up`): `flexible_time_window { mode = "OFF" }`, `schedule_expression_timezone = var.scale_schedule.timezone`,
     target `arn = "arn:aws:scheduler:::aws-sdk:eks:updateNodegroupConfig"`, `role_arn` = the role,
     `input = jsonencode({ ClusterName = module.eks.cluster_name, NodegroupName = local.node_group_name, ScalingConfig = { DesiredSize = 0 } })`
     (and `var.scale_schedule.up_desired` for `up`). Add a `retry_policy { maximum_retry_attempts = 3 }`.
   - Comment: why desired-only (M13), and that the EKS control plane still runs (M20).
5. `outputs.tf`: `scale_schedule_names` (list, empty when off).
6. Tests (new file `tests/schedule.tftest.hcl`, same mock style as `endpoint.tftest.hcl`, `enable_karpenter = false`):
   default has no schedule resources; with `scale_schedule = {}` and `min_size = 0` there are 2 schedules and 1 role;
   with `scale_schedule = {}` and `min_size = 1` → `expect_failures = [var.scale_schedule]`;
   `instance_types = ["t4g.small"]` + `ami_type = "AL2023_x86_64_STANDARD"` → expect failure;
   `instance_types = ["m6i.large"]` + `ami_type = "AL2023_x86_64_STANDARD"` → plan succeeds.
   If the mocked `node_group_id` makes `split` fail, add `override_module` / `mock_resource` the way the existing test mocks data, and note it in the report.
7. Wire dev: `_envcommon/compute/eks.hcl` inputs add `scale_schedule = try(local.env_vars.locals.scale_schedule, null)`.
   `workloads-dev/env.hcl`: `min_size = 0` with comment "0 so the night schedule can scale to zero (PLAN 9.5)", and
   `scale_schedule = {}` (defaults: weekdays 07-19 Berlin). **Prod env.hcl is not touched.**

Verify: `make verify-module MODULE=compute/eks` → ok. `cd workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/compute/eks && terragrunt render --format json | jq '.inputs | {min_size, scale_schedule}'` → `min_size: 0`, `scale_schedule: {}`. If `render` needs credentials, write that down and skip it.

## Part 6 — Cost janitor module (dev, report-only)

Commit: `feat(cost-janitor): weekly report of orphaned EBS, snapshots, EIPs and log groups without retention (PLAN 9.5)`

### 6a. `iac-modules-repo/governance/cost-janitor/` — copy the layout of `security/auto-remediation` (M17)

Files: `versions.tf` (aws `>= 6.0`, archive `>= 2.4`, terraform `>= 1.9.0`), `variables.tf`, `main.tf`, `outputs.tf`, `README.md`,
`src/cost_janitor.py`, `tests/cost_janitor.tftest.hcl`, `tests/__init__.py`, `tests/test_cost_janitor.py`.

Variables: `name` (default `"cost-janitor"`, same regex validation as billing's `name`), `dry_run` (bool, default `true`),
`volume_min_age_days` (14), `snapshot_min_age_days` (30), `default_log_retention_days` (30, validated against the set
CloudWatch accepts: 1,3,5,7,14,30,60,90,120,150,180,365,400,545,731,1096,1827,2192,2557,2922,3288,3653),
`exclude_log_group_prefixes` (list, default `[]`), `schedule_expression` (default `"cron(0 6 ? * MON *)"`),
`schedule_timezone` (default `"Europe/Berlin"`), `alert_topic_arn` (string, default `null`), `log_retention_days`
(for the Lambda's own log group, default 30), `tags`.

`main.tf`:
- `archive_file` → `.build/cost_janitor.zip`. Log group `/aws/lambda/<name>` with retention. `aws_lambda_function`
  `python3.13`, timeout 300, memory 256, env `DRY_RUN`, `VOLUME_MIN_AGE_DAYS`, `SNAPSHOT_MIN_AGE_DAYS`, `DEFAULT_LOG_RETENTION_DAYS`,
  `EXCLUDE_LOG_GROUP_PREFIXES` (comma-joined), `ALERT_TOPIC_ARN` (empty when null). Inline Checkov skips **with reasons**,
  same ones auto-remediation uses where they apply. Run Checkov and add only what it actually reports.
- IAM role for Lambda: always `ec2:DescribeVolumes`, `ec2:DescribeSnapshots`, `ec2:DescribeImages`, `ec2:DescribeAddresses`,
  `logs:DescribeLogGroups` on `*`; logs write to its own log group; `sns:Publish` on `alert_topic_arn` only when set.
  **Only when `dry_run = false`** (a `dynamic` statement or a separate policy with `count`): `ec2:DeleteVolume`,
  `ec2:DeleteSnapshot`, `ec2:ReleaseAddress` with condition `StringNotEquals` `aws:ResourceTag/keep` = `true`; and
  `logs:PutRetentionPolicy` on `arn:<partition>:logs:<region>:<account>:log-group:*`.
- Schedule: `aws_scheduler_schedule` invoking the Lambda (role trusted by `scheduler.amazonaws.com` with `aws:SourceAccount`,
  `lambda:InvokeFunction` on this function only).

`src/cost_janitor.py` (every AWS call through a client argument; paginate with `client.get_paginator(...)`):
- `find_unattached_volumes(ec2, now, min_age_days)`: `status=available`, `CreateTime` older than min age.
- `find_old_snapshots(ec2, now, min_age_days)`: `OwnerIds=["self"]`, older than min age, **excluding** snapshots used
  by any own AMI (`describe_images(Owners=["self"])` block device mappings) and any with a tag key starting `aws:backup:`.
- `find_unassociated_eips(ec2)`: `describe_addresses`, no `AssociationId`.
- `find_log_groups_without_retention(logs, exclude_prefixes)`: no `retentionInDays`, name not starting with an excluded prefix.
- `is_kept(tags)`: tag `keep` with value `true` (case-insensitive) → skipped and listed as "kept".
- `act(...)`: only when `DRY_RUN` is not `"true"`: delete volumes/snapshots, release EIPs, put retention. One failure must not stop the rest; collect errors.
- `handler(event, context)`: builds clients, runs all finders, acts or not, logs **one JSON summary line**
  (`{"dry_run":..., "unattached_volumes":[...], "old_snapshots":[...], "unassociated_eips":[...], "log_groups_without_retention":[...], "kept":[...], "errors":[...], "estimated_monthly_usd": ...}`)
  and publishes a short text version to SNS when `ALERT_TOPIC_ARN` is set.
- `estimate_monthly_usd(volumes, snapshots, eips)`: rough, labelled as an estimate in the summary:
  gp3 $0.08/GB-month, other volume types $0.10, snapshots $0.05/GB-month (VolumeSize as upper bound), EIP $3.60/month.
  Put these constants at the top with a comment "eu-central-1 list prices, approximate. Check before quoting".

Python tests (`tests/test_cost_janitor.py`, fake clients with `get_paginator` returning an object whose `paginate(**kw)` yields pages):
volume younger than min age is ignored; attached volume ignored; snapshot used by an AMI ignored; `aws:backup:` snapshot ignored;
`keep=TRUE` volume listed under kept and never deleted; dry run calls no delete method (fake records calls); act mode
deletes the right IDs and continues after one `delete_volume` raises; log group with an excluded prefix ignored;
estimate math for 1×100 GB gp3 + 1 EIP = $11.60.

Terraform test (`tests/cost_janitor.tftest.hcl`, mock provider like auto-remediation's): default plan has **no**
delete actions in any policy JSON (assert `!strcontains(<policy json>, "ec2:DeleteVolume")`); with `dry_run = false`
the delete statement exists and contains `aws:ResourceTag/keep`; an invalid `default_log_retention_days = 31` → `expect_failures`.

### 6b. Dev leaf + release wiring

- `workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/governance/cost-janitor/terragrunt.hcl`: **inlined** (M16):
  `include "root"`, a `terraform { source = local.module_source }` built exactly like `_envcommon/governance/budgets.hcl`'s
  `locals` (pinned tag vs `IAC_MODULES_LOCAL`), `module_versions.cost_janitor`, `inputs = { dry_run = true, tags = { ManagedBy = "Terragrunt-Wrapper" } }`.
  Comment at the top: "Report-only. Read the first weekly summary in CloudWatch Logs before setting dry_run = false. Dev only, never prod."
- `workloads-dev/env.hcl` `module_versions`: `cost_janitor = "cost-janitor-v1.0.0"`.
- `release-please-config.json`: entry like `guardrail-signals` (`terraform-module`, package/component `cost-janitor`, `tag-separator "-"`).
  `.release-please-manifest.json`: `"iac-modules-repo/governance/cost-janitor": "1.0.0"`. Keep both files valid JSON (`python3 -m json.tool`).
- `Makefile` `docs` target: one line for `iac-modules-repo/governance/cost-janitor`.
- `AGENTS.md` §2 table: one row (Account (workload, dev), `cost-janitor-v1.0.0`, one-line purpose incl. "report-only by default").
- Add `iac-modules-repo/governance/cost-janitor/.gitignore` containing `.build/`. **Don't copy auto-remediation here:**
  its `.build/remediate_open_ssh.zip` is committed to git and nothing ignores `.build/` (checked 2026-10-11:
  `git ls-files | grep .build`). Check with `git status --short` after `make verify-module` that no zip is staged.

Verify: `make verify-module MODULE=governance/cost-janitor` → ok; `cd iac-modules-repo/governance/cost-janitor && python3 -m unittest discover -s tests` → OK.

## Part 7 — Document it (docs)

Commit: `docs(finops): document the cost gate, weekly report, night schedule and janitor (PLAN 9.5)`

`docs/FINOPS.md`:
- New section "🤖 Cost automation (PLAN 9.5)" near the top, as a plain table (no Mermaid, AGENTS.md §9): Stage
  (PR / weekly / nightly / weekly) · What runs · Where in the repo · Status (`built, not applied` for all).
- The cost gate rule exactly as built (thresholds, `cost-approved`, re-run the job after adding the label, per account).
- Night schedule: 64 % fewer node hours (M20), control plane unchanged, desired-only because of M13.
- Janitor: report-only first, `keep=true` opt-out, how to switch to act mode, dev only.
- "Savings Plans rule (design only)": buy a 1-year **Compute** Savings Plan for about 70-80 % of the steady
  baseline after 3 months of data, using Cost Explorer's recommendation; never cover dev or spiky usage; review
  coverage and utilisation monthly. Mark it 🔴 not applied.
- A "Measured" table with empty rows the owner fills after applying: cost gate first real result, first weekly
  report total, dev node hours before/after, janitor first-run estimate. Put "not yet" in each cell. **Don't invent numbers.**

`docs/CICD.md`: add `finops-weekly.yml` to the workflow list and the cost gate to the gate list (one line each, match the file's style).

---

## Rules this task can break (copied from AGENTS.md / owner rules)

1. **Never edit** `.checkov.yaml`, `.trivyignore`, `policy-library-repo/`, `.claude/settings.json`, `.claude/hooks/`. Accept a Checkov finding only with an inline `#checkov:skip=<ID>: <reason>` on that resource. (AGENTS.md §7 rule 3)
2. **After every edit inside a module**, run `make verify-module MODULE=<category/name>`. After **3** failed runs in a row on the same module, stop and hand over with the last result. Fix the code, not the check. (rules 1 and 4)
3. **Never run** `apply`, `destroy`, `import`, `state *`, `force-unlock`, or `run --all` with a mutating command. No AWS credentials, no default profile: offline only. (rule 2; owner memory)
4. **Never hand-write** `provider.tf` / `backend.tf`. Modules have no provider blocks (billing uses `configuration_aliases`). (AGENTS.md §7)
5. `fmt` must pass across all four roots: `terraform fmt -recursive iac-modules-repo foundation-live-repo workloads-live-repo policy-library-repo` and `terragrunt hcl fmt`. (AGENTS.md §3/§7)
6. Never invent account IDs, emails or measured cost numbers. Placeholders stay placeholders; "not yet" stays "not yet". (rule 5; PLAN)

## Verify sequence (run in this order at the end; look at the output, not only the exit code)

```bash
export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache
git switch -c feat/p9-5-finops-automation   # at the START, before Part 1

# 1. Formatting
terraform fmt -check -recursive iac-modules-repo foundation-live-repo workloads-live-repo policy-library-repo
terragrunt hcl fmt --check            # flag confirmed for Terragrunt 1.0.3; exit 0 = formatted

# 2. Modules (compare against baseline M19)
make verify-module MODULE=governance/billing        # expect: validate FAIL with the us_east_1 alias message ONLY; test PASS
make verify-module MODULE=governance/organization   # expect: ok
make verify-module MODULE=compute/eks               # expect: ok
make verify-module MODULE=governance/cost-janitor   # expect: ok

# 3. Python
python3 -m unittest discover -s workloads-live-repo/scripts/tests -v 2>&1 | tail -40   # LOOK: the new test names are listed and pass
(cd iac-modules-repo/governance/cost-janitor && python3 -m unittest discover -s tests -v)

# 4. The gate on real fixture input: read the printed verdict and the markdown, not just the exit code
cp /dev/null /tmp/gate.md
python3 workloads-live-repo/scripts/cost_gate.py workloads-live-repo/scripts/tests/fixtures/infracost_increase_large.json --markdown-out /tmp/gate.md; echo "exit=$?"   # expect exit=1, "❌"
python3 workloads-live-repo/scripts/cost_gate.py workloads-live-repo/scripts/tests/fixtures/infracost_increase_large.json --labels "foo,cost-approved" --markdown-out /tmp/gate.md; echo "exit=$?"  # expect exit=0, "approved by label"
python3 workloads-live-repo/scripts/cost_gate.py /nonexistent.json; echo "exit=$?"   # expect exit=2
cat /tmp/gate.md    # both verdicts present (append, not overwrite)

# 5. Report renders offline with the fakes: covered by tests; also check the import guard
python3 -c "import ast,sys; t=ast.parse(open('workloads-live-repo/scripts/cost_report.py').read()); print([n.names[0].name for n in t.body if isinstance(n,(ast.Import,ast.ImportFrom)) and 'boto' in (getattr(n,'module',None) or n.names[0].name)])"   # expect []

# 6. Checkov over everything, incl. the new workflow
make checkov

# 7. JSON files still valid; workflow YAML parses
python3 -m json.tool release-please-config.json >/dev/null && python3 -m json.tool .release-please-manifest.json >/dev/null && echo json-ok
python3 -c "import yaml,sys; [yaml.safe_load(open(f)) for f in ['.github/workflows/finops-weekly.yml','.github/workflows/reusable-terragrunt.yml']]; print('yaml-ok')"

# 8. FinOps doc claims gone, and nothing outside scope changed
grep -n "Intelligent-Tiering\|Senior Engineer\|Node Termination Handler" docs/FINOPS.md   # expect nothing
git diff --stat main...HEAD     # every path must be in the Scope table
git log --oneline main..HEAD    # 7 commits, messages as given
```

`make test` runs `conftest verify` and every module's `terraform test`. Run it once at the end too. It's slow; if
a module **outside** scope fails, check it also fails on `main` (`git stash` isn't needed: use
`git worktree add --detach /tmp/base main` and run the same command there), and report it, don't fix it.

## Done means

- [ ] 7 commits on `feat/p9-5-finops-automation`, one per part, messages as above. Nothing pushed.
- [ ] `docs/FINOPS.md` has none of the three false claims (M1) and has the automation section with "not yet" measured cells.
- [ ] `cost_gate.py` exits 1 / 0 / 0-with-label / 2 on the verify inputs, and appends its Markdown; the workflow fails the PR only after the comment is posted, only on `pull_request`.
- [ ] Billing plans both enrollment resources by default; the org list has both new principals.
- [ ] `finops-weekly.yml` skips cleanly when management isn't in the matrix, and updates instead of duplicating the week's issue on re-run.
- [ ] EKS uses an ARM AMI type for Graviton instances (validated); dev has `min_size = 0` + `scale_schedule = {}`; prod is unchanged.
- [ ] `cost-janitor` default plan contains no delete permission; act mode's deletes are tag-conditioned; tests prove dry run deletes nothing.
- [ ] All verify steps above give the expected output; the billing validate failure is the baseline one only.

**Report back:** the commit list; for each verify step, the command and the key output line(s); every place you
deviated from this plan and why (for example a provider argument name that differed); and a **"not checked"** list.
It must at least include: the real Infracost JSON shape (first CI run), boto3 in the toolchain image, Scheduler's
`aws-sdk:eks:updateNodegroupConfig` input accepted by AWS, Compute Optimizer enrollment region behaviour, and anything that needed AWS.

## Out of scope (discussed, left out on purpose)

- **Rego rule `deny_gp2`** (block `gp2` volumes in `aws_ebs_volume`, launch template `block_device_mappings`, `aws_db_instance.storage_type`): **owner writes it**, because `policy-library-repo/` is human-only (rule 1). Add it to `POLICIES.md` with the reason "org rule: gp3 is cheaper and faster; Checkov has no equivalent".
- Applying anything, and filling the "Measured" table: owner, after apply.
- RDS night stop: no RDS is deployed in dev today.
- Karpenter controller install / consolidation: separate item.
- Savings Plans purchase: design text only.
- An Infracost `--compare-to` baseline from `main`: the plan JSON already carries prior state, so `breakdown` gives past vs new (M4). Revisit only if the first CI run shows `pastTotalMonthlyCost` is always null.
- Changing the drift-detection or apply jobs.
- The committed build artifact `iac-modules-repo/security/auto-remediation/.build/remediate_open_ssh.zip` (should be
  ignored and rebuilt by `archive_file`): separate small PR, owner's call.
