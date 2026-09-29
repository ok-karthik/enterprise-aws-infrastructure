# Execution log

One dated entry per finished task or PR: what changed, how it was checked, and what was skipped or did not pass.
Moved out of `PLAN.md` on 2026-09-28 (PLAN 10.8). Newest entries go at the bottom. The plan is [`PLAN.md`](../PLAN.md).

- **2026-08-25 → 2026-08-27** — IaC Generation Agent Phases A–D finished and verified (see
  *Completed history*).
- **2026-09-21** — Plan rewritten for the multi-account enterprise target (Phases 0–9 + IDP
  follow-ups). The old unfinished items were moved in: E → 8.2, F → 8.3/8.4, G (Renovate) → 1.5.
- **2026-09-21 (cont.)** — Checked the plan against the job-market data (467 Senior+ infra
  ads). Added the Priority track, apply-mode/cost table, 2.8 budgets, 4.9 auto-remediation,
  EU regulations in 4.7, 9.3 platform SLOs, 9.4 delivery metrics and Phase 10 (evidence and
  Staff signal). Marked 8.2 low priority.
- **2026-09-21 (cont.)** — Added the Parallel learning track (owner console work and model PRs,
  day by day), with orders 1–6 of the Priority track targeted for 2026-09-27.
- **2026-09-21 (Phase 0, branch `feat/p0-fix-current-layout`)** — Phase 0 implemented in one PR. Nothing
  was applied and no AWS credentials were used for any check (credential files blanked; the shell's
  default profile is a different account, `174160028427`, and was deliberately not used).
  - **Account:** the management/dev/prod account is now `954171757349` (was `508768430433`) in all four
    `account.hcl` files. The new account gets a fresh state bucket (`tg-state-954171757349-…`), so there is nothing to migrate.
    **You still need to:** run `infrastructure-bootstrap/bootstrap.sh` in that account, then set the four new repo
    variables and create the `dev` / `prod` GitHub Environments (the script prints the commands).
  - **0.1** `root.hcl` (live + bootstrap) now takes the account ID from `account.hcl`, so `allowed_account_ids` is a real check.
    Also switched `_envcommon/data/s3.hcl` and the S3 catalog template off `get_aws_account_id()`.
    Checked: `terragrunt render` shows `allowed_account_ids = ["954171757349"]` and the matching bucket name. I did **not**
    run a wrong-account `init` to see it fail (would need AWS access); `bootstrap.sh` has its own preflight, tested with a stubbed `aws`
    (no credentials → exit 1; wrong account → exit 1, nothing changed).
  - **0.2** Replaced the single `repo:*` admin role with `github-actions-plan` (ReadOnly + state read + `*.tflock` write; trusts
    `pull_request` and `refs/heads/main`) and `github-actions-apply` (Admin + `github-actions-apply-boundary`; trusts only
    `environment:dev` / `environment:prod`). Workflows use `AWS_<ENV>_PLAN_ROLE_ARN` / `AWS_<ENV>_APPLY_ROLE_ARN`;
    docs updated in `docs/CICD.md`. **Found while doing this:** the old bootstrap leaves pointed at `iam-github-oidc-role` /
    `iam-github-oidc-provider`, which do not exist in `terraform-aws-modules/iam` v6.6.0 (they became `iam-role` with
    `enable_github_oidc` and `iam-oidc-provider`), so bootstrap was already broken; fixed. Checked with `terragrunt hcl validate --inputs`
    (inputs valid against the real v6.6.0 modules). **Not checked:** the trust and boundary policies were not run against AWS or the IAM policy simulator.
    `bootstrap.sh` was rewritten (account preflight, plan → confirm → apply, prints `gh` commands) after comparing with your
    `sumup-platform-challenge/platform/bootstrap`; ideas kept from there: a hardened state bucket and printed wiring commands.
  - **0.3** ACK spoke role: dropped `IAMFullAccess` + `AmazonS3FullAccess`; added scoped inline policy
    (`var.ack_s3_bucket_prefix`, `var.ack_role_path`, `iam:PermissionsBoundary` on create/attach/put) and the `ack-tenant-boundary` policy.
    Differences from the text: `DeleteRole*` was narrowed to `DeleteRole` / `DeleteRolePolicy` / `DetachRolePolicy` (the glob also matches
    `DeleteRolePermissionsBoundary`), and `iam:PassRole` has no boundary condition because AWS does not evaluate that key for PassRole
    (it would make PassRole unusable); it is limited to the role path instead. Tested with `terraform test` (mock provider).
    Also fixed an existing bug found by the test: the OU policy attachments used `for_each` over apply-time IDs and could never be created from scratch; now statically keyed (`root_id` is `""` in live, so no state is affected).
  - **0.4** `deny_outside_eu_central_1` → `deny_unapproved_regions` with `moved {}`, driven by `var.allowed_regions` (validated non-empty), exempt global services extended (also `cur`, `aws-portal`, `fms`, `wafv2`, `waf-regional`, based on AWS's sample SCP; extendable with `additional_region_exempt_actions`). Policy name changes to `deny-unapproved-regions` (in-place update).
  - **0.5** EKS: removed the `0.0.0.0/0` fallback; `api_allowed_cidrs` must be non-empty when public access is on (cross-variable validation, so module needs Terraform ≥ 1.9). Public access now **defaults to off**, and `env.hcl` `api_allowed_cidrs = []` keeps the endpoint private. **Effect on dev:** on the next apply the dev cluster API becomes private-only; add your egress CIDR to `infrastructure-live/dev/env.hcl` first if you need laptop `kubectl`.
  - **0.6** `PlatformAdmin` → `PlatformEngineer` (PowerUser + inline IAM limited to `role/platform/*`, admin-policy attachment denied; optional `permissions_boundary_arn`). New `BreakGlassAdmin` (Admin, 1h, never assigned by this module). Output `platform_admin_permission_set_arn` renamed → **breaking output change** for the module. No live leaf uses it.
  - **0.7** `single_nat_gateway` moved to `env.hcl` (dev `true`, prod `false`). Prod has `enable_nat_gateway = false` today, so nothing changes until prod NAT is enabled.
  - **0.8** Added `deny_admin_attachments`, `deny_public_s3`, `deny_open_ingress`, `deny_iam_wildcards`, `require_encryption` (+ `helpers.rego`), and `require_service_tag.rego` → `require_tags.rego` with `Owner` / `DataClassification` (added to `default_tags` from `account.hcl`). `conftest verify`: 58/58 pass, and a hand-made bad plan is caught. **Not done / differences:** (a) the "443-to-private" case is not implemented, a plan cannot tell a public ALB SG from a private one; (b) SQS accepts SSE-SQS as well as KMS (the Karpenter queue uses SSE-SQS); (c) the "existing plans still pass" check needs a real plan, which needs AWS access, so **CI on this PR is the check**. To avoid a known failure I set `encrypted = true` on the EKS node launch-template volume (an unencrypted mapping would trip `require_encryption`). **Effect:** on the next dev apply the node group rolls to a new launch template. Also added the conftest and module `terraform test` suites to the CI static-analysis step and `make test` (`conftest verify` was not run in CI before).
  - **0.9** Removed the `Project = "Infrastructure-Automation"` override from all three `_envcommon` files (org, vpc, eks), the bootstrap role inputs and the IaC agent's catalog templates. Resources will get an in-place tag update.
  - **Checks run:** `terraform fmt -check` (4 roots), `terragrunt hcl fmt --check`, `terraform validate` (org, eks, human-access), `terraform test` (11 tests), `conftest verify` (58), `tflint --recursive` (clean), `trivy config` (no CRITICAL/HIGH), `.agents` unit tests + eval (pass; 2 fixtures skipped, no LLM key), `bash -n` on `bootstrap.sh`. **Not run:** `smoke-test.sh` (needs credentials for `terragrunt init`; the pre-commit hook for it was skipped with `SKIP=platform-smoke-test` on these commits for that reason, the other hooks ran), real `plan`s, any `apply`. Run `./infrastructure-live/scripts/smoke-test.sh` yourself once logged in to `954171757349`. Checkov's HCL scan lists many pre-existing findings; the CI static Checkov step is `soft_fail`.
- **2026-09-21 (plan change, Day-0 bootstrap)** — The owner confirmed `954171757349` is the **management (payer)
  account** and greenfield. Added **2.0**: the Day-0 bootstrap moves to CloudFormation (a plain stack in
  management, plus service-managed StackSets per OU for member accounts). This **replaces** the Phase 0 note
  "run `infrastructure-bootstrap/bootstrap.sh`": don't run the Terragrunt bootstrap. Knock-on edits:
  2.2 (no `assume_role`; bucket name drops the alias), 2.5 (bucket and CI roles removed; they come from 2.0),
  2.6 (direct OIDC per account instead of a shared-services hub), 3.4 and 4.6 (role names, protecting the
  bootstrap resources), and ADR 3 in 10.1. Plan text only; no code changed.
- **2026-09-21 (plan change, 2.0 detailed)** — Owner decision: CloudFormation for Day-0 plus native
  Terraform for Organizations; no Control Tower / AFT; CI/CD and networking go in the Infrastructure
  OU, and Security holds only log-archive and security-tooling. 2.0 is split into 2.0a (template spec,
  one-time CLI commands, `infrastructure-bootstrap/` cleanup list) and 2.0b (StackSets). Plan text only.
- **2026-09-21 (cont.)** — Disabled the `platform-smoke-test` pre-commit hook on commit (`stages: [manual]` in `.pre-commit-config.yaml`): it needs real AWS credentials for the account in `account.hcl`, so it failed on every commit. Re-enable it (delete that line) once the PLAN 2.0-2.6 setup is done. The other hooks (fmt, whitespace, trivy) still run.
- **2026-09-21 (2.0a, branch `feat/p2-cfn-bootstrap`, from `feat/p0-fix-current-layout`)** — Day-0 CloudFormation bootstrap
  for the management account `954171757349` (task 2.0a only; 2.0b not started). No AWS command was run: the only `aws` calls
  were to a stub script, and no credentials were used.
  - **Added** `infrastructure-bootstrap/cloudformation/account-bootstrap.yaml` and `stack-policy.json`; **rewrote** `bootstrap.sh`
    (reads account, owner, data classification and region from `infrastructure-live/_global/{account,region}.hcl`; needs `AWS_PROFILE`
    or key env vars, never the default profile; org + StackSets access; change set with confirm, `--yes` to skip; "stack exists" →
    update path; "no changes" → success; termination protection, stack policy, prints `gh` wiring) and `README.md`.
    **Deleted** `infrastructure-bootstrap/root.hcl` and all of `dev/`.
  - **Ported before deleting:** I rendered the old boundary and plan-role units and compared them with the template by script:
    every statement (Sid, Effect, Actions, Resources) matches, the old `DenyOrganizationAndIdentityCenter` is split into
    `DenyOrganizationsAndAccount` (only `!If DenyOrganizations`) + always-on `DenyIdentityCenter` (same action union), and the three
    plan-role inline statements and trust subjects match. New statements: `DenyOrgDestruction`, `ProtectStateBucket`, `ProtectBootstrapStack`.
  - **Other files:** `infrastructure-live/root.hcl` bucket is now `tg-state-${account_id}-${region}` (`s3_bucket_tags` and the auto-create
    note removed); `infrastructure-bootstrap` removed from the fmt lists (`Makefile`, `.pre-commit-config.yaml`, static-analysis action,
    `smoke-test.sh`, `iac_agent.py`) and kept in `.checkov.yaml`; `cfn-lint` added to pre-commit and to the static-analysis action;
    docs updated (`AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/CICD.md`, `visualizer.html`).
  - **Checked (offline):** `cfn-lint` clean (also confirms `ThumbprintList` is not required); `checkov -f` on the template: 24 passed,
    0 failed, 1 skipped (`CKV_AWS_18` access logging, reason in the template; the plan's `CKV_AWS_145` KMS skip is also in the template,
    but this Checkov version does not flag it); `shellcheck` clean and `bash -n` (shellcheck caught a backtick in an error message that would
    have run `delete-stack`; fixed); stubbed-`aws` runs of 7 scenarios (no profile, no credentials, wrong account: exit 1 with no mutating
    call; fresh create; existing stack with no changes: nothing executed; declined prompt: change set and empty stack discarded, nothing
    executed; ROLLBACK_COMPLETE: fails, `delete-stack` not called); `terragrunt render` on the org leaf shows bucket
    `tg-state-954171757349-eu-central-1` and `allowed_account_ids = ["954171757349"]`; repo-wide `git grep`: no `infrastructure-bootstrap/dev`
    reference and no command that passes `--backend-bootstrap` (only prose that forbids it); `terraform fmt`, `terragrunt hcl fmt --check`,
    `conftest verify` (58), `tflint`, `trivy config` (no CRITICAL/HIGH), `.agents` tests and eval all pass.
  - **Not checked:** the template was never deployed or run through `aws cloudformation validate-template` or a real change set (that needs
    AWS access); the trust and boundary policies were not run through the IAM policy simulator; `smoke-test.sh` was not run (needs credentials).
    The `cfn-lint` pre-commit hook fetches its repo (`v1.57.0`) on first use.
  - **Left as is, flagging:** (1) with the apply variables unset (as 2.0a-2 says) the `apply-dev` / `apply-prod` jobs on `main` will run without
    credentials and fail, which also triggers the pipeline healer; consider `if: vars.AWS_*_APPLY_ROLE_ARN != ''` on those jobs (not done, it is
    not in 2.0a). (2) `DISASTER_RECOVERY.md` still mentions DynamoDB locking. (3) The live `dev` / `prod` leaves keep account `954171757349` until 2.1.
- **2026-09-21 (2.0b, branch `feat/p2-bootstrap-stacksets`, from `main` after PR #49)** — Code for 2.0b only. Nothing was applied and no
  AWS command or credentials were used.
  - **Added** module `governance/bootstrap-stacksets` (`aws_cloudformation_stack_set` per GitHub Environment, `SERVICE_MANAGED`, auto-deployment
    with retain-on-removal, 25% concurrency, zero failure tolerance; `aws_cloudformation_stack_set_instance` per StackSet in the primary region only,
    `retain_stack = true`; `AllowOrganizationsAdmin` hardcoded to `"false"`; template body is an input), release-please entries at `1.0.0`, a live
    leaf `infrastructure-live/_global/governance/bootstrap-stacksets` + `_envcommon` blueprint, and `policies/terraform/deny_member_org_admin.rego`
    (fails a plan where a bootstrap StackSet sets `AllowOrganizationsAdmin` to anything but `"false"` or is not named `bootstrap-*`).
  - **Deviations from the request in chat (please confirm):** (1) three StackSets (`bootstrap-nonprod`, `bootstrap-prod`, `bootstrap-core`), not one
    `platform-member-bootstrap`: auto-deployment can only use the StackSet's own parameters, so a single set would give every new account the same
    `GitHubEnvironment` (apply-role trust subject). (2) Names start with `bootstrap-`: the apply boundary only protects `StackSet-bootstrap-*` stacks.
    (3) Deployed from Terraform (as 2.0b says), not by hand in the console, so it is reviewable and drift-checked.
  - **OU IDs are placeholders** (`ou-0000-00000000`, `TODO(owner)`); the module refuses to plan while any remain. Not applied: 2.0b also needs the OUs to exist.
  - **Repo now matches the live stack** after your two manual edits (PR #49): thumbprints and `PlanRole` `StringLike repo:<repo>:*`. I updated the
    stale comments/docs. Two flags: the plan role now trusts *any* job of the repo (it is read-only but can read all state files, and member accounts inherit
    it through the StackSet); and the second thumbprint (`1c5876bd...`) differs from the value I remember as GitHub's published one (`1c58a3a8...`).
    I could not check offline, and AWS does not validate GitHub thumbprints, so it is harmless, but please verify.
  - **Checked (offline):** `terraform validate`, `terraform test` (8 for the new module; the 11 existing still pass), `conftest verify` (63), `cfn-lint`,
    `checkov -f` on the template (24 passed / 0 failed / 1 reasoned skip), `terragrunt hcl validate --inputs` and `render` on the new leaf, `tflint`,
    `trivy config`, `terraform fmt`, `terragrunt hcl fmt --check`, `.agents` tests. **Not checked:** a real plan/apply, the StackSet against AWS, and that a
    new account in an OU actually receives the stack ("Done when (2.0b)").
  - **Review of the current `governance/organization` SCPs (your item 2), nothing changed here:** it has deny-leave-organization, deny-CloudTrail-tampering
    and the region allow-list (`allowed_regions`, Phase 0.4). "Protect security services" (GuardDuty / Config / Security Hub / Access Analyzer / Macie) is
    **not** there: that is 4.6 and only makes sense once those services are enabled. All three SCPs attach to two hardcoded OUs (Production,
    NonProduction) and nothing is created while `root_id = ""` (live). 2.3 replaces the OUs and moves the ACK resources out.
  - **Not done, and why:** (a) *Apply of the org stack / vending accounts*: implementing agents never apply (rule 4), and the OUs and `account-factory`
    do not exist yet (2.3, 2.4 are separate PRs). (b) *Pipeline alignment / retargeting dev and prod roles*: needs the vended accounts and the account
    registry first (2.1, 2.6). The management `_global` stack is already outside the workflows (they only run `infrastructure-live/dev` and `prod`).
    (c) The OU layout in the chat message (Core / Workloads / Sandbox) differs from PLAN 2.3 (Security, Infrastructure, Workloads{Prod,NonProd}, Sandbox,
    Policy-Staging, Suspended); I followed the plan.
- **2026-09-21 (Phase 1, branch `feat/p1-repo-topology`, on top of `feat/p2-bootstrap-stacksets`)** — Tasks 1.1–1.6 and 1.8 done; **1.7 not done**
  (separate PR in `internal-developer-platform`, and it needs tags that exist at the new path first). Nothing applied, no AWS credentials used. All Phase 2
  work from `feat/p2-bootstrap-stacksets` is kept and now lives in its Phase 1 home (the StackSets leaf and blueprint are in `foundation-live-repo/`,
  `bootstrap.sh` and the CloudFormation template are in `foundation-live-repo/_bootstrap/`). This branch is stacked: merge order is Phase 2 (2.0b) first, then this.
  - **1.1** `git mv infrastructure-modules iac-modules-repo`; release-please config and manifest, CI, pre-commit, Makefile, Checkov, CODEOWNERS, `.agents/**`
    (prompts, `iac_agent.py`, tests) and docs updated; `iac-modules-repo/CODEOWNERS` added.
  - **1.2** `foundation-live-repo/` = `_global` (organization, bootstrap StackSets), `_envcommon/governance`, `_bootstrap`, `root.hcl`;
    `workloads-live-repo/` = `dev`, `prod`, `_envcommon/{compute,data,network}`, `scripts`, `root.hcl`. The two `root.hcl` files are identical copies.
    **State keys verified:** I rendered all 6 leaves before the move and after each step; keys and bucket names are byte-identical.
  - **1.3** `git mv policies policy-library-repo`; conftest paths in CI, the static-analysis action, Makefile, smoke test and `iac_agent.py`
    (`build_policy_digest` and the conftest gate); the digest still finds the rules.
  - **1.4** `module_versions` maps in `workloads-live-repo/{dev,prod}/env.hcl` and `foundation-live-repo/_global/env.hcl`; the four `_envcommon` blueprints build
    `terraform.source` from them or from the checkout when `IAC_MODULES_LOCAL` is set (both modes checked with `terragrunt render`).
    **Tags created before the rename point at the old path, so no module has a usable release tag yet:** the pins are set to the current manifest versions but
    unusable, and the workflows and `smoke-test.sh` set `IAC_MODULES_LOCAL=1` until each module is released again (for example one
    `feat(<module>): relocate to iac-modules-repo` commit per module). Then remove the variable from the four workflows. I did not create releases or tags.
    The IaC agent's generated `_envcommon` files still use the checkout path (new modules have no tag).
  - **1.5** Renovate: a custom manager for the `module_versions` maps plus one rule per module and environment (own PR, no automerge, dev and prod separate).
    Checked: `renovate-config-validator` passes and the regex extracts exactly the 6 pins; **not** run in Renovate itself, so how it groups PRs is unproven.
  - **1.6** `smoke-test.sh` loops over both live repos (env names, region checks, fmt of four roots) and validates dev; workflows use `workloads-live-repo/{dev,prod}`;
    `.agents/AGENTS.md` §3 fmt command covers `iac-modules-repo foundation-live-repo workloads-live-repo policy-library-repo`; `.checkov.yaml`, tflint and Infracost updated.
  - **1.8** `docs/adr/0001-repository-topology.md` is a **draft written by a model**, marked as such at the top: rewrite it in your own words (Phase 10).
  - **Checked (offline):** state-key comparison above, `terragrunt hcl validate --inputs` on all 6 leaves (local mode), `terraform fmt` (4 roots),
    `terragrunt hcl fmt --check`, `conftest verify` (63), `terraform test` for all modules (`make test`), `cfn-lint`, `shellcheck`, `tflint`, `trivy config`,
    `.agents` tests and eval, workflow YAML parse, `git grep` for stale old paths (only a deliberate explanation in `docs/CICD.md` remains).
    **Not checked:** a real plan or `terragrunt init` (needs credentials, so `smoke-test.sh` was only run up to its init step), the workflows on GitHub, Renovate itself.
- **2026-09-21 (2.3, branch `feat/p2-org-v2`, stacked on `feat/p1-repo-topology`)** — Organization module v2 and the ACK split. Nothing applied, no AWS
  credentials used.
  - **`governance/organization` v2:** manages the organization itself (`feature_set = ALL`, `aws_service_access_principals`, `enabled_policy_types` = SCP, RCP,
    tag, backup, declarative EC2), the OU tree from `var.organizational_units` (two levels; default Security, Infrastructure, Workloads{Prod,NonProd}, Sandbox,
    Policy-Staging, Suspended), and the three baseline SCPs. Outputs `organization_id`, `root_id`, `management_account_id`, `organizational_unit_ids` (name → id),
    `guardrail_policy_ids`. Breaking: the old `Production` / `NonProduction` OUs, `root_id` input and ACK inputs/outputs are gone (nothing was deployed: `root_id` was `""`).
  - **ACK moved** to the new module `identity/ack-cross-account` (per-account), code and its 3 tests unchanged; release-please entry added at `1.0.0`.
  - **Decisions to confirm:** (1) the SCP guardrails attach to `Policy-Staging` **only** by default (`guardrail_target_ous`), so a policy is tested before it can lock real
    accounts out; widen it deliberately. (2) `aws_service_access_principals` and `enabled_policy_types` are **authoritative**: apply disables anything enabled by hand and not
    in the list. The default keeps StackSets access (needed by 2.0b) and includes Identity Center and the services PLAN phases 3 to 6 use. Read the plan before applying.
  - **Before the owner applies:** the organization and any hand-made OUs must be **imported** (`terragrunt import ...`); the live leaf lists the exact commands.
  - **Checked (offline):** `terraform validate`, `terraform test` (9 for the organization module, 3 for `ack-cross-account`), `terragrunt hcl validate --inputs` on the leaf,
    `tflint`, `trivy config`, `terraform fmt`, `terragrunt hcl fmt --check`. **Not checked:** a real plan (needs the import and AWS access), the SCP JSON against AWS.
- **2026-09-21 (2.1 + 2.4, branch `feat/p2-account-factory`, stacked on `feat/p2-org-v2`)** — Account registry and account factory. Nothing applied, no AWS
  credentials used, no account created.
  - **2.1** `foundation-live-repo/_config/accounts.hcl` (management keeps `954171757349`; every other id and every email is a placeholder marked `TODO(owner)`),
    `_config/regions.hcl` (primary `eu-central-1`, secondary `eu-west-1`, `allowed_regions_by_ou`), and `workloads-live-repo/scripts/check-account-registry.sh`
    (fails if any `account.hcl` uses an ID that is not in the registry; run by the smoke test and the static-analysis action). Checked with a positive run and a
    negative run on a tampered `account.hcl`. **Not done from 2.1:** the region SCP still takes one global `allowed_regions`; per-OU lists are wired in with 4.6.
    Placeholder emails use `@example.com`, not your real address, to keep it out of the repo.
  - **2.4** New module `governance/account-factory` (`aws_organizations_account`, `close_on_deletion = false`, `prevent_destroy`, IAM billing access allowed, OU from the
    registry), release-please entry at `1.0.0`, `_envcommon` blueprint (dependency on the organization stack for OU IDs) and leaf
    `foundation-live-repo/_global/governance/account-factory`.
  - **Addition to the plan:** each registry entry has `create = true|false`. Only `create = true` entries (log-archive, security-tooling, workloads-dev) reach the factory,
    so the placeholders (network-hub, shared-services, workloads-prod) and the management account can never be created by accident. The module also refuses an
    `@example.com` email, a duplicate email and an unknown OU, so a registry entry you have not filled in fails at plan time. **Please confirm the `create` flag.**
  - **Before the owner applies:** fill in the real emails and IDs; **import** the accounts you already created by hand (`terragrunt import ...`, commands in the leaf); apply the
    organization stack first (its OU IDs feed the factory).
  - **Checked (offline):** `terraform validate`, `terraform test` (5), `terragrunt hcl validate --inputs` and `render` on the leaf (exactly the 3 `create = true` accounts are
    passed), `shellcheck`, `tflint`, `trivy config`, `conftest verify` (63), fmt, `.agents` tests. **Not checked:** a real plan or apply, the imports.
  - **Still open in Phase 2:** 2.2 (account-first layout, `root.hcl` rework, state-key migration), 2.5 (account-baseline), 2.6 (CI identity chain and the pipeline retargeting
    to vended accounts), 2.7 (discovery contract per account), 2.8 (budgets). Not started; 2.2 changes state keys and needs your run of the migration script.
- **2026-09-21 (rest of Phase 2: 2.2, 2.5, 2.6, 2.7, 2.8)** — Implemented offline, in five commit series (branches `feat/p2-account-baseline-and-layout`,
  `feat/p2-account-baseline-module`, `feat/p2-discovery-and-budgets`, `feat/p2-ci-account-matrix`, each stacked on the previous). Nothing applied, no AWS credentials
  used, no account or resource created. **PLAN item 2.0b and 2.0 were ticked as you asked; the 2.0b "Done when" (a new NonProd account gets its bucket and roles and a PR can
  plan against it) is not verified.**
  - **2.2** Account-first layout: `foundation-live-repo/management/{account.hcl,env.hcl,_global,eu-central-1}` and `workloads-live-repo/workloads-{dev,prod}/...`.
    `account.hcl` now has `ou`, `env`, `account_alias`; `root.hcl` (both identical copies) reads `env` from it and has no `assume_role` (`allowed_account_ids` stays). The
    registry check now verifies folder name, id, OU and env against the registry (positive run plus 4 negative runs). `smoke-test.sh` takes an account directory, and gets
    regions and envs from `_config/regions.hcl` (2 negative runs). `migrate-state-keys.sh` is dry-run by default, owner only, and refuses to start while any account id is a
    placeholder (tested against a stub: 0 `aws` calls, then all 7 moves with real-looking ids). **State keys change** (`dev/...` becomes `workloads-dev/...`,
    `_global/...` becomes `management/_global/...`) and the workload buckets follow the workload accounts; nothing was applied, so there is no state to move.
    **`workloads-dev` / `workloads-prod` `account.hcl` now carry the registry's placeholder ids (`000000000005` / `...06`)**: no stack can run there (`allowed_account_ids`) until you fill in the real ids in
    `foundation-live-repo/_config/accounts.hcl` and both `account.hcl` files.
  - **2.5** `governance/account-baseline` (9 tests): `platform-workload-boundary` (a role under it can only create roles with the same boundary; no user/access-key creation; can't edit
    `platform-*` / `terraform-*` / `github-actions-*` roles, security services, or the account defaults), account alias, strict password policy, S3 account Block Public Access, EBS
    encryption by default, IMDSv2 default, two rotating KMS keys, account/kms/boundary discovery parameters. Leaves for management, workloads-dev, workloads-prod.
    `deny_iam_wildcards` allow-lists the boundary. **Deviation:** the aliases in `account.hcl` (`ok-karthik-...`) are guesses, marked `TODO(owner)`; they must be globally unique.
  - **2.7** `governance/discovery-publisher` (4 tests) is the single owner of `vpc/*`, `eks/*`, `ack/*` names; the VPC and EKS blueprints now set `publish_ssm_parameters = false` so two
    resources never share a name. `docs/DISCOVERY_CONTRACT.md` documents the full contract; the `.agents/AGENTS.md` table is updated. The publisher does not yet publish
    `ack/cross_account_role_arn` (no ack-cross-account stack exists in any account).
  - **2.8** `governance/budgets` (5 tests): monthly budget with alerts at 50/80/100 % actual and 100 % forecast, plus a per-service Cost Anomaly Detection monitor. `monthly_budget_usd` per
    account is in the registry (management 50). **Deviation: USD, not EUR** (AWS Budgets reports in USD). The alert address is the account's registry `email`; the module refuses `@example.com`,
    so **the budgets leaves fail at plan time until you replace the placeholder emails**. The amounts other than management's are my guesses (`TODO(owner)`).
  - **2.6** Workflows run over an account matrix generated from the registry by `workloads-live-repo/scripts/generate_account_matrix.py` (10 unit tests). An account runs only with `ci = true`, a
    live folder and a **real** id; roles are built from the id (`arn:aws:iam::<id>:role/github-actions-plan|apply`), so the four `AWS_<ENV>_*_ROLE_ARN` variables are gone (only `AWS_REGION`
    remains). `apply` runs one account at a time (management, core, dev, staging, prod), only after every plan and governance job passed, in the account's GitHub Environment.
    `drift-detection.yml` and `destroy.yml` use the same matrix (`destroy` takes an `account`, resolves it through the script, and refuses `management`). `bootstrap.sh`, its README,
    `docs/CICD.md`, `GOVERNANCE.md` and `AGENTS.md` are updated. **Consequences to know:** (1) the matrix is **empty today** (both workload accounts have placeholder ids and management has
    `ci = false`), so a PR runs static analysis only: **no plan, OPA, Checkov or cost job runs until you fill in real ids**, and the empty-matrix jobs are skipped, not failed. (2) Required status
    checks in branch protection are now per account (`workloads-dev / 📝 Plan: workloads-dev` ...); the old `Dev / ...` / `Prod / ...` names no longer exist, so **update branch protection**
    or PRs will wait on checks that never appear. (3) The CloudFormation output descriptions changed (text only); re-run `bootstrap.sh` to see the change set.
  - **Checked (offline):** `terraform fmt` and `terragrunt hcl fmt --check`; `conftest verify` (64); `terraform test` for every module; `terragrunt hcl validate --inputs` on all 15 leaves;
    the generator's and the agent's unit tests; the registry check and the offline smoke-test steps (with negative cases); `shellcheck` on every script; `cfn-lint`; `actionlint` on the 8 workflows
    (and it catches a deliberate typo); `tflint`; `trivy config`; YAML/JSON parse. **Not checked:** a real plan or apply, `terragrunt init`/`validate` per account (needs credentials, so the smoke test's graph step and
    the workflows were never run on GitHub), the boundary and SCP JSON against AWS, Renovate's PR grouping, and the imports the owner must run.
  - **Still open in Phase 2:** the owner steps above (real ids and emails, imports, `ci = true` for management, branch protection). **1.7** (IDP repo) is complete; the **2.0b "Done when"** remains open for owner deployment.
- **2026-09-21 (Phase 3: 3.1-3.6, branches `feat/p3-identity-center`, `feat/p3-break-glass`, `feat/p3-apply-boundary`, `feat/p3-root-access-analyzer`, each stacked on the previous)** —
  Implemented offline. Nothing applied, no AWS credentials used, no resource created. 3.4 and 3.6 are `[~]` for the reasons below.
  - **3.1 / 3.2** New module `identity/identity-center` (16 tests) owns the whole catalog, groups and assignments. Catalog: `ReadOnly`, `Developer`, `PlatformEngineer`, `SecurityAudit`, `Billing`,
    `BreakGlassAdmin`. Assignments are `OU -> group -> permission set`, expanded with the registry (real account ids only). Groups are read from SCIM (or created with `manage_groups`). ABAC:
    `team` and `cost_center` session tags. Guardrails refuse a bad assignment at plan time: `BreakGlassAdmin` never static, `PlatformEngineer` / `BreakGlassAdmin` not static in Prod, `Developer` only in
    NonProd / Sandbox / Policy-Staging, unknown sets/groups, placeholder ids. `Developer` = customer-managed policy `platform-developer` + boundary `platform-workload-boundary`, attached by name; **`platform-developer`
    is new in `governance/account-baseline`** (ABAC on EC2 by the team tag; published as `iam/developer_policy_arn`, added to the discovery contract). `identity/human-access` lost its permission sets
    (**breaking**, nothing used them) and keeps only EKS access entries. `docs/IDENTITY.md` covers the manual IdP and SCIM steps. **Decisions to confirm:** (1) I read "1h for admin-level sets" as `BreakGlassAdmin`
    **and** `PlatformEngineer` (it can change IAM); the rest get 8h. (2) The catalog was **merged into identity-center** (the plan allowed either place) so `PlatformEngineer` and `BreakGlassAdmin` are not defined twice.
    (3) The ABAC attribute paths (`${path:enterprise.department}`, `${path:enterprise.costCenter}`) are my guess for a SCIM enterprise extension: **check them against your IdP** (`TODO(owner)`); the IdP group names in the
    leaf are placeholders too.
  - **3.3** New module `security/break-glass-alerts` (7 tests): EventBridge rules for `AssumeRoleWithSAML`, console sign-in and (management only) the Identity Center portal calls, an SNS topic **encrypted with its own
    rotating KMS key** (the org's own `require_encryption` rule demands it), one email subscription per address. Leaves in management, workloads-dev and workloads-prod; the address is the account's registry email and the module
    refuses `@example.com`, so **these leaves fail at plan time until you replace the placeholder emails**, and each address must confirm the SNS subscription. `docs/BREAK_GLASS.md` has the JIT design (AWS TEAM or a SaaS
    equivalent: request, approve by someone else, time-limit, log to log-archive), a setup checklist, the runbook, what to do on an unexpected alert, when the tool or the IdP is down, and a drill.
    **Not delivered:** the JIT tool itself (it is a product you deploy; I could not check the current AWS TEAM install guide offline). **Not verified:** the CloudTrail event field names in the rules (especially the portal rule, whose
    fields differ between `Federate` and `GetRoleCredentials`): confirm them in the drill. The rules only see events in their own region.
  - **3.4 (half done)** The apply-role **boundary** now also denies switching off GuardDuty / Config / Security Hub / Macie / Inspector / Access Analyzer, editing `platform-*` / `terraform-*` roles and
    `OrganizationAccountAccessRole`, deleting `platform-workload-boundary` and removing any role's boundary (organizations, account, SSO, CloudTrail and the CI-identity protections were already there). Checked by an offline test
    that parses the template (structure, both `AllowOrganizationsAdmin` variants, 3,865 of the 6,144 allowed characters, CI roles), plus `cfn-lint` and `checkov -f` (24 passed, 0 failed, same reasoned skip). **Not done:** the role is
    **still `AdministratorAccess`**. Replacing it with "the managed policies for the services actually used" needs real applies to know which services, and a wrong list would break CI apply silently, so I left it: generate the policy from
    CloudTrail with Access Analyzer policy generation after the first real applies. **Two consequences:** the apply role can no longer update `platform-*` roles (a stack must not name its roles that way), and the change reaches management
    through `bootstrap.sh` and members through an update of the bootstrap StackSets (both are owner steps, documented in the bootstrap README). I deliberately did **not** deny editing `platform-workload-boundary` versions: the baseline stack
    updates it with `CreatePolicyVersion`, so only deleting it is denied.
  - **3.5** `governance/organization` now has `aws_iam_organizations_features` (`RootCredentialsManagement`, `RootSessions`; default on; refuses to plan without trusted access for `iam.amazonaws.com`) and
    `aws_organizations_delegated_administrator` (real ids only, only for services with trusted access). 15 organization tests (6 new). `docs/ROOT_ACCESS.md` explains removing member root credentials and doing a privileged task with
    `sts:AssumeRoot`. **The task-policy names and the CLI call are from memory (I could not check the AWS docs): confirm them.** The code does not delete existing root credentials: that is the one-off procedure in the doc.
  - **3.6 (`[~]`)** New module `security/access-analyzer` (3 tests): an organization analyzer for external access and one for unused access (default 90 days), in the `security-tooling` account, which the org leaf registers as
    delegated administrator **only once its registry id is real**. New folder `foundation-live-repo/security-tooling` (placeholder id, `ci = false`, matches the registry). **Not done / not verified:** "findings go to Security
    Hub" is not something this code configures: it happens on its own once Security Hub is enabled with the same delegated administrator, which is PLAN 4.4. Unused-access analysis is billed per role analyzed.
  - **Checked (offline):** `terraform fmt` and `terragrunt hcl fmt --check`; `conftest verify` (64); `terraform test` for all 13 modules with tests (two needed a rerun after a transient provider-download timeout, both passed);
    `terragrunt hcl validate --inputs` on all 20 leaves; the account-matrix generator (10) and bootstrap-template (9) tests; the IaC agent tests; the registry check and the offline smoke-test steps; `shellcheck`; `cfn-lint`; `actionlint`;
    `tflint`; `trivy config`; YAML/JSON parse. **Not checked:** a real plan or apply of anything, `terragrunt init` per account, the IAM policies against the policy simulator, Identity Center behaviour (attribute paths, customer-managed policy by name),
    and the workflows on GitHub.
  - **New tag rule followed:** the three new modules (`identity-center`, `break-glass-alerts`, `access-analyzer`) are registered with `"tag-separator": "-"` at `1.0.0` in
    `release-please-config.json` and `.release-please-manifest.json`. The changed modules (`account-baseline`, `organization`, `human-access`) keep their entries; release-please will propose their next versions from the commits (`human-access` is a breaking change).
- **2026-09-21 (plan change, tooling and contract)** — Added 3.7 (tighten the Developer policy behind the PR #62
  Checkov findings), 2.9 (versioned discovery contract), 8.9 (one scanner per job: tflint, blocking Checkov,
  conftest for org rules, Trivy for the image only) and 8.10 (split rules between Checkov and Rego with one
  catalog). Gemini's "DynamoDB → S3 native locking" topic was already done: no DynamoDB lock table exists and
  both `root.hcl` files set `use_lockfile = true`. Plan text only.
- **2026-09-21 (PR #62 Checkov fix, `governance/account-baseline`)** — The code-scanning Checkov check failed on `aws_iam_policy.developer` (`CKV_AWS_286/287/288/289/290/355`, from the SARIF)
  **and on `aws_iam_policy.workload_boundary`** (the same six plus `CKV_AWS_62`, `CKV_AWS_63`, `CKV2_AWS_40`), so fixing only the Developer policy would have left the check red. I reproduced the exact IDs locally with `checkov -d`.
  - **Developer policy: four explicit Deny statements.** `DenyResourcePolicyWrites` (`s3:PutBucketPolicy`, `s3:DeleteBucketPolicy`, `s3:PutBucketAcl`, `s3:PutObjectAcl`, `s3:PutBucketPublicAccessBlock`,
    `sqs:AddPermission`, `sns:AddPermission`, `lambda:AddPermission`, `lambda:CreateFunctionUrlConfig`, `ecr:SetRepositoryPolicy`); `DenyPlatformParameterWrites` (`ssm:PutParameter`, `DeleteParameter`,
    `DeleteParameters`, `LabelParameterVersion`, `AddTagsToResource` on `parameter/platform/*` in this account; reads stay allowed); `DenySsmAccessToOtherTeamsInstances` (`ssm:SendCommand` / `StartSession` on EC2 and
    managed instances unless `aws:ResourceTag/team` equals `${aws:PrincipalTag/team}`); and `DenySsmAccessWithoutTeamTag` (a caller with no team tag cannot use them at all: without it, an unresolved tag variable
    is not a safe comparison). Instances only: SSM documents stay allowed. 5 new `terraform test` runs (14 in the module, all pass) check the exact action lists, the resource ARNs, the ABAC conditions, that reads and documents stay
    allowed, and that the policy has exactly these four Denies.
  - **Finding worth knowing: the Denies do not clear any Checkov finding.** Checkov's IAM checks read only the Allow statements and do not subtract Denies (before and after had the identical six IDs), so the Denies are real
    hardening but the skips are what turns the check green. **Skips** (`#checkov:skip` on the resource, one per ID with its own reason): NonProd/Sandbox-only permission set (PLAN 3.2, enforced by `identity-center`),
    `platform-workload-boundary`, the explicit Denies, and the SCP/RCP data perimeter (4.6). The boundary's skips say why a permissions boundary must `Allow */*` and then Deny.
  - **Known gap, not fixed (not in the requested list):** `sqs:SetQueueAttributes` and `sns:SetTopicAttributes` can still set a queue/topic **policy**, which bypasses the `AddPermission` Deny, and `lambda:UpdateFunctionUrlConfig`
    is not denied. Denying them outright would break normal queue/topic configuration and there is no condition key for "which attribute", so the data perimeter (4.6) is the real backstop. Say if you want them denied anyway.
  - **Checked (offline):** `terraform fmt`, `validate`, `terraform test` (14), `checkov -d` on the module (20 passed, 0 failed, 16 skipped) and a run with the repo's `.checkov.yaml` (0 findings in `account-baseline`), `conftest verify` (64).
    Not run: the GitHub check itself, any apply, any AWS access. **Included in this commit:** the pending `PLAN.md` edits from the other session (new task 2.9, the discovery contract as a versioned API), as you asked.
- **2026-09-21 (plan change, review of Phases 0–3)** — Offline check of Phases 0–3 (credentials blanked): `terraform fmt`,
  `terragrunt hcl fmt` (both live repos), `conftest verify` (64), `terraform test` for all 11 modules that have tests (79 pass;
  the Phase 3 entry says 13 modules, but 11 have a `tests/` folder), `terraform validate` on every module (`workload-identity`
  failed once on a provider-download timeout and passed on rerun), `tflint --recursive`, bootstrap template `cfn-lint` +
  `checkov -f` (24 pass, 0 fail) + pytest (9), `shellcheck`, `bash -n`, the account registry check, matrix tests (10) and
  `.agents` tests (11). **Found:** the apply boundary always denies `sso:*`, so CI can't apply Identity Center (new task 3.8).
  Also ticked 3.7 (done by the other session, commit `a3208b6`) with its two follow-ups. Rewrote 8.9: local/CI parity for
  Checkov, move the repo-wide `CKV_AWS_111` / `CKV_AWS_356` skips inline, plan-stage Checkov on every plan file, the
  tool-per-job table. Noted in 4.6 that RCPs close the SQS/SNS policy gap from 3.7.
- **2026-09-21 (3.8 and the first 3.7 follow-up, branch `feat/p3-boundary-followups`, from `main`)** — Offline only: no AWS credentials, nothing applied.
  - **3.8** The apply boundary's `DenyIdentityCenter` (`sso:*`, `sso-directory:*`, `identitystore:*`) is now conditional on a new template parameter `AllowIdentityCenterAdmin` (`"true"`/`"false"`,
    default `"false"`, condition `DenyIdentityCenter`), the same pattern as `AllowOrganizationsAdmin`. `bootstrap.sh` passes `true` for management (checked against the stub `aws`: the change set has
    `AllowIdentityCenterAdmin=true`). The StackSets never do: `governance/bootstrap-stacksets` hardcodes `"false"` (new test), and `deny_member_org_admin.rego` now also fails a plan where a bootstrap
    StackSet sets it to anything else (2 new Rego tests, 66 total). The template test (13, was 9) now models both switches and all four combinations: member = both denies, management = neither, and the two
    switches are independent (allowing Identity Center does not allow Organizations, and the other way round). The organization-destruction deny stays on where Organizations are managed. Updated the "Always on"
    comment, the bootstrap README (parameters, the boundary row, the hand-run command) and `docs/CICD.md` / `docs/IDENTITY.md`. `cfn-lint` clean; `checkov -f` unchanged (24 passed, 0 failed, same reasoned skip);
    the boundary is still well under the 6,144-character limit in all four combinations. **Owner step:** re-run `bootstrap.sh` (it shows a change set: the new parameter and a `Modify` on `ApplyBoundary`)
    **before** the first Identity Center apply from CI. The StackSets pick the change up on the next `terragrunt apply` of `bootstrap-stacksets` (a new parameter value on each StackSet).
  - **3.7 follow-up 1** `DenyResourcePolicyWrites` no longer contains `lambda:CreateFunctionUrlConfig`. A new `DenyPublicLambdaFunctionUrls` denies `lambda:CreateFunctionUrlConfig` **and**
    `lambda:UpdateFunctionUrlConfig` when `lambda:FunctionUrlAuthType = NONE`, so IAM-authenticated (`AWS_IAM`) URLs are allowed and public ones are not, and an `AWS_IAM` URL cannot be switched to `NONE`.
    `lambda:AddPermission` stays denied (it is how a public URL is made invokable). Three new/changed `terraform test` runs (15 in the module): the exact actions, the condition, and that no Deny of
    function URLs is unconditional. **Limit:** an `Update` that does not touch the auth type has no `FunctionUrlAuthType` key, so it is allowed: an already-public URL is not fixed by this, it just cannot be
    created or switched to. `checkov -d` on the module: still 20 passed, 0 failed, 16 skipped. **Second 3.7 follow-up** (queue/topic policies via `SetQueueAttributes` / `SetTopicAttributes`) is unchanged: accepted here
    and closed by the RCP data perimeter in 4.6.
  - **Included in this commit:** the other session's pending `PLAN.md` edits (tasks 3.7 follow-ups, 3.8, and any other plan text in the working tree): they were only in the working tree, so the tasks did
    not exist on `main` until this commit.
  - **Checked (offline):** `terraform fmt` / `validate` / `test` for `account-baseline` (15) and `bootstrap-stacksets` (9); template tests (13); `conftest verify` (66); `cfn-lint`; `checkov -f` and `checkov -d`; `shellcheck`
    and a stub-`aws` run of `bootstrap.sh`. **Not checked:** the change set against AWS (`validate-template`, a real change set), the policy in the IAM simulator, or any apply.

- **2026-09-21 (cont.)** — **8.9 steps 1–4, 6, 7** (branch `feat/p8-scanner-gates`; step 5, removing `trivy config`, deliberately not done).
  - **Why local and CI differed (step 1):** the CI action scanned `.github` too and downloaded external modules, while `.checkov.yaml` listed three directories and a nested `_bootstrap` path. Now one settings file:
    `.checkov.yaml` scans `iac-modules-repo`, `foundation-live-repo`, `workloads-live-repo` and `.github`, with `download-external-modules: false` (the plan-stage scan sees the resolved values, and the static
    external-module scan gave a false positive on `CKV_AWS_37`). `workloads-live-repo/scripts/run-checkov.sh` runs it (used by CI, `make checkov` and the `checkov` pre-commit hook) and warns if the local Checkov
    differs from `CHECKOV_VERSION` in the toolbox Dockerfile (pinned to 3.3.19, Renovate-managed).
  - **Backlog (step 2):** now 0 findings locally (`run-checkov.sh`). Fixed instead of skipped: postgres `iam_database_authentication_enabled`, `copy_tags_to_snapshot`, `auto_minor_version_upgrade`,
    `enabled_cloudwatch_logs_exports`; s3 lifecycle rule aborting incomplete multipart uploads; `pipeline_healer.yml` explicit `permissions`; Dockerfile Checkov pin. Skipped inline with a reason: postgres
    CKV_AWS_157 (multi-AZ costs money, PLAN 7.3), 293 (deletion protection while `skip_final_snapshot`), 118, 353, 382, CKV2_AWS_30; s3 CKV_AWS_145, 18, 144, CKV2_AWS_62; Dockerfile CKV_DOCKER_2, 8.
    `soft-fail-on: LOW` and `soft_fail` are gone. Tests: `terraform test` for postgres (1 run) and s3 (2 runs).
  - **Step 3:** `CKV_AWS_111` and `CKV_AWS_356` are out of the repo-wide skip list. **Nothing fires offline** without them (no inline skips were needed), so this is proven for the static scan only. Whether the plan-stage
    scan flags IAM policies inside upstream modules cannot be known without a real plan: if it does, add the exception with a reason.
  - **Step 4:** the plan-stage step now loops over **every** `tfplan.json` (one Checkov run each, fails if any fails, fails if there are none) and `merge_sarif.py` merges the results into one SARIF per account
    (deduplicated). Simulated the exact workflow step with two fixture plans (one clean, one with an open SSH group): scanned 2, exit 1, one merged SARIF with the finding once. The old `head -n 1` step
    would have missed the second plan.
  - **Step 6:** `publish-toolchain.yml` now builds (`load: true`), scans with `trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` (Trivy version read from the Dockerfile), and only then pushes.
    `make image-scan` does the same locally. **`--ignore-unfixed` is a decision for the owner:** without it a CVE with no available fix would block every rebuild.
  - **Step 7:** `GOVERNANCE.md`, `docs/CICD.md`, `.agents/AGENTS.md` updated (gate table, commands).
  - **Checked (offline):** Checkov 0 findings; `actionlint`; 7 unit tests for `merge_sarif.py`; `terraform fmt` / `validate` / `test` for postgres and s3. **Not checked:** a real CI run (the action and workflow changes),
    a real plan, the image build and scan (Docker is not running here), the pre-commit hook on a full commit. **Owner steps:** merge, then the toolbox image is rebuilt by `publish-toolchain.yml` on `main`; until then CI
    uses the old image without the pinned Checkov.
- **2026-09-21 (plan change, repo review)** — Added from a holistic review: 2.10 (Karpenter/cluster contract
  for the IDP, rewritten so `discovery-publisher` stays the only writer, because the IDP's draft put the
  parameters in `compute/eks`, where publishing is off in live), 2.11 (first real plan in CI, since nothing has
  been planned against AWS since the multi-account move), 3.9 (break-glass rules may miss `us-east-1`
  events), 10.8 (move this log out), a standing guardrail (no Kubernetes API from Terraform), rule 3 (no
  stacked branches), and notes on 10.1 (only ADR 0001 exists) and 10.4 (README claims that are out of date).
  Plan text only.

- **2026-09-21/22 (Priority track order 5, branch `feat/p4-security-baseline`, from `main` plus the unmerged
  `docs/plan-review-tasks` commit)** — 4.1, 4.2, 4.4, 4.5, 4.6 (SCPs + RCPs only), 4.9, in that order, one
  commit each so 4.6 (the SCP/RCP commit) can be reviewed on its own first, per the request.
  - **4.1** `security/log-archive`: one Object Lock bucket (COMPLIANCE, 400 days for CloudTrail/Config, 90 for
    the rest) per log type in the `log-archive` account, one KMS key, bucket policies scoped to the delivering
    service and `aws:SourceOrgID`. Bucket/trail names are a **naming contract** with `security/org-cloudtrail`
    (same prefix and trail name), not shared state. 10 `terraform test` runs. Checkov: `CKV_AWS_19`/`145` fixed
    properly (split the SSE config into two resources, one per algorithm, instead of a conditional inside one);
    4 inline skips left with reasons. Live leaf added with a placeholder account id (`ci = false`).
  - **4.2** `security/org-cloudtrail`: one multi-region, organization-wide trail in the management account,
    log file validation on, encrypted with the log-archive key, delivering to the log-archive bucket. Also
    added (Checkov `CKV_AWS_252`/`CKV2_AWS_10`, and genuinely useful): a local CloudWatch Logs group (its own
    KMS key — CloudWatch Logs needs one in-account, can't use the cross-account log-archive key) and an SNS
    topic for log-delivery notifications. Optional S3 data events for confidential buckets, optional CloudTrail
    Lake. 7 `terraform test` runs (two needed `command = apply`: several AWS provider attributes here are
    Optional+Computed, so the mock provider leaves them unknown at plan time even when the config sets them).
  - **4.4** `security/threat-detection`: GuardDuty (S3 data events, EKS audit + runtime monitoring with the
    `EKS_ADDON_MANAGEMENT` sub-feature, EBS malware protection, RDS login events, Lambda network logs),
    Security Hub (FSBP + CIS v3, cross-region finding aggregation from the primary region), Inspector v2 (EC2,
    ECR, Lambda), Macie, optional Detective — all auto-enabled organization-wide from `security-tooling`.
    **Fixed a gap from this same commit's own live-layer change:** `governance/organization`'s
    `delegated_administrators` only registered `access-analyzer.amazonaws.com`; without also registering
    guardduty/securityhub/inspector2/macie there, this module's org auto-enable would fail at a real apply.
    Added those four to the `organization.hcl` envcommon (in the 4.6 commit, since that's where the file was
    already touched). 10 `terraform test` runs.
  - **4.5** `security/security-alerts`: one EventBridge rule per alert type (GuardDuty/Security Hub findings,
    root sign-in, root API calls, Organizations policy changes), one encrypted SNS topic, applied with
    different `enable_*` flags in security-tooling (findings) and management (root/SCP changes — root
    credentials and Organizations only exist there). BreakGlassAdmin sign-in is already `security/break-glass-alerts`
    and is not duplicated. 7 `terraform test` runs; one needed `command = apply` (same Optional+Computed reason).
  - **4.6, most carefully checked (this is the one a bad SCP could lock accounts out from):**
    - `governance/organization`: replaced the single org-wide region SCP with **one policy per OU**
      (`var.allowed_regions_by_ou`), attached only to its own OU (**breaking**: removed `var.allowed_regions`).
      Added to the generic guardrail set (still `guardrail_target_ous`, Policy-Staging only by default):
      `deny_root_user_actions` (matches the literal `:root` ARN, not a `sts:AssumeRoot` break-glass session —
      different ARN shape, see docs/ROOT_ACCESS.md), `deny_disable_detection_services` (same action list as
      account-baseline's `DenySecurityServiceTampering`, so both layers agree), `deny_iam_user_creation` and
      `protect_platform_resources` (both exempt break-glass and the StackSets service-linked role — **SCPs
      cannot use a `Principal`/`NotPrincipal` element at all**, so every exception is a `Condition` matching an
      assumed-role ARN pattern), `require_imdsv2` (flagged compatibility risk: `compute/eks`'s node groups may
      not set `metadata_http_tokens = "required"` yet — check before widening past Policy-Staging),
      `deny_role_creation_without_boundary` (mirrors account-baseline's own boundary condition, including its
      known gap: a `CreateRole` call that omits `iam:PermissionsBoundary` entirely is not caught by
      `StringNotEquals` alone). Sandbox guardrails (large instances, RI/Savings Plan purchases) are **opt-in**
      (off by default: Sandbox is the owner's free-experimentation account). Suspended deny-all is on by
      default but safe by construction (that OU starts empty). Confirmed no Terraform-managed role is
      currently named `platform-*`/`github-actions-*` (grepped the repo), so `protect_platform_resources` has
      no overlap with normal CI applies even if widened. 23 `terraform test` runs (up from 12); one inline
      Checkov secrets-scanner skip on a test assertion line (`CKV_SECRET_6`, false positive on an IAM
      condition key/value string — first time this repo has needed one).
    - New `governance/data-perimeter`: RCPs for S3, KMS, SQS, Secrets Manager (deny non-org access, require
      TLS), attached to Policy-Staging only by default. Closes the second half of the PLAN 3.7 gap for **SQS**
      (a queue policy set through `sqs:SetQueueAttributes` can no longer grant outside access, since the RCP
      still denies it at the resource side). **SNS is still not covered**: RCPs do not support it at the time
      this was written — confirmed by first writing an SNS RCP and hitting the "action must not straddle two
      services" problem for the STS exemption, which is what led to scoping STS the way described below.
      **`sts` is a supported service but is NOT in the default `enabled_services`** (`["s3","kms","sqs","secretsmanager"]`):
      an RCP on STS also covers `sts:AssumeRoleWithWebIdentity` (GitHub OIDC) and `sts:AssumeRoleWithSAML`
      (Identity Center federation) — the actions that create the org's first session, which have no
      `aws:PrincipalOrgID` **yet**. Turning `sts` on denies an explicit list of other STS actions (not a
      wildcard, since `Action` and `NotAction` cannot both appear in one statement) minus
      `var.sts_federation_exempt_actions`. 10 `terraform test` runs.
    - **Safety, since this was the priority:** every new/changed policy defaults to no effect beyond
      Policy-Staging (or, for Sandbox/Suspended, to exactly that one OU) — nothing widens without a deliberate
      change to `guardrail_target_ous` / `allowed_regions_by_ou` / `target_ous` / `enabled_services`.
  - **4.9** `security/auto-remediation`: a Lambda in security-tooling that revokes an open `0.0.0.0/0`/`::/0`
    ingress rule on port 22/3389 and tags the group `remediated-by=auto`. **Cross-account event delivery**:
    EventBridge only sees events for its own account (a known limitation, separate from the org trail in 4.2),
    so a member account's `AuthorizeSecurityGroupIngress` event is forwarded to a new central bus in
    security-tooling (added to `governance/account-baseline`: a `security-remediation` role, created only when
    given the Lambda's role ARN). **Not built:** the second trigger PLAN 4.9 asks for (the matching Config
    rule) — PLAN 4.3 (the org Config recorder) is out of scope for this PR, so there is no Config rule yet;
    documented in the module README as the thing to add once 4.3 exists. Python (`src/remediate_open_ssh.py`,
    full type hints, `from __future__ import annotations`): 18 `unittest` tests with hand-written fake clients
    (no `moto`/`boto3` install — neither was in this environment, and installing them costs the owner's mobile
    data; the PLAN text allows either "moto or stubbed boto3"). `boto3` is imported lazily inside `handler()`
    so the pure, tested functions never need it importable. **mypy not run** (not installed here); the code
    passes `python3 -m py_compile`. Terraform: `data.archive_file` zips `src/` at plan time (no Docker/CI build
    step yet); 6 `terraform test` runs (one needed `command = apply`, same Optional+Computed reason).
    `docs/runbooks/auto-remediation.md` has the steps to measure the removal time (target < 30s) — **not
    measured**, that needs a real deployment.
  - **Checked (offline, across all six):** `terraform fmt`, `terraform validate`, `terraform test` for every
    touched/new module (log-archive 10, org-cloudtrail 7, threat-detection 10, security-alerts 7, organization
    23, data-perimeter 10, auto-remediation 6, account-baseline 18 — 91 runs total); Checkov with the repo
    config on every touched/new module (0 failed everywhere Checkov has rules for the resource types involved;
    `aws_organizations_*` resources have no Checkov rules at all in the installed version — confirmed this is
    a pre-existing gap, not something hidden by a parsing failure, by testing the old, already-merged
    `governance/organization` main.tf in isolation and seeing the same 0/0); `tflint`; `conftest verify` (66);
    `IAC_MODULES_LOCAL=1 terragrunt hcl validate --inputs` on every new/changed live leaf (management,
    security-tooling, log-archive, workloads-dev, workloads-prod); pre-commit hooks on every commit.
  - **Not checked:** a real plan or apply anywhere (no AWS credentials used, none of the "owner steps" in the
    various module READMEs were done); the toolbox image (no Docker running here, same as the 8.9 PR); mypy
    (not installed); the auto-remediation removal-time measurement; whether AWS Config really has no rule to
    react to yet is only true because PLAN 4.3 wasn't done in this PR, not independently verified against AWS.
  - **Left for the owner to decide, in the PR description:** widening `guardrail_target_ous` /
    `allowed_regions_by_ou` / the data-perimeter `target_ous` past Policy-Staging (test there first, per the
    task's own instruction); whether/when to add `sts` to `governance/data-perimeter`'s `enabled_services`;
    checking `compute/eks`'s IMDSv2 defaults before widening `require_imdsv2`; wiring
    `security_remediation_lambda_role_arn` and a per-account forwarding EventBridge rule once the Lambda is
    for real deployed; running the auto-remediation timing drill.

- **2026-09-22 (Phase 5, branch `feat/p5-networking`, from `main` — PR #66 / feat/p4-security-baseline was
  already merged into `main` by the time this started, so this branch has both)** — 5.1 through 5.7, one
  commit each (5.6 folded into 5.2's commit: both attach to the same transit gateway, so one module).
  network-hub and shared-services flipped to `create = true` in the account registry (still placeholder
  ids): PLAN 5.x is what makes them "needed", matching log-archive/security-tooling's precedent.
  - **5.1** `network/ipam`: a top-level pool, one regional pool per region, prod/nonprod env pools per
    region; **only the env pools** are RAM-shared with the Workloads OU (not the wider pools), so a workload
    account can only ever request from its own environment's slice. `network/vpc` gets
    `ipv4_ipam_pool_id`/`ipv4_netmask_length` as an alternative to `cidr` (**breaking**: `cidr` is now
    optional, a variable validation requires exactly one mode). **Found and fixed a real bug** while writing
    the IPAM test: the default network ACL's "allow from inside the VPC" rule referenced `var.cidr` directly,
    which is empty in IPAM mode (the real CIDR is only known after AWS allocates it at apply) — it now falls
    back to the platform's whole IPAM address space (`10.0.0.0/8`) unless the caller supplies the tighter
    range explicitly. Recreated `foundation-live-repo/_config/organization.hcl` on this branch (it only
    existed on the by-then-unmerged `feat/p4-security-baseline`); harmless once both are on `main`.
  - **5.2 (+ 5.6)** `network/transit-gateway`: default route association/propagation off, `prod`/`nonprod`/
    `shared`/`inspection` route tables. The transit gateway **itself** (not a route table) is RAM-shared with
    the Workloads and Infrastructure OUs. `accept_vpc_attachments` (explicit spoke acceptance, matching "the
    acceptance side is in network-hub") **defaults to off and stays off through the transit gateway's first
    apply**: on that apply the transit gateway does not exist yet, so a `for_each` built from a data source
    that reads it back cannot resolve — a real Terraform limitation, confirmed while writing the test, not a
    guess. Cross-region peering: this module applied once per region, coordinated through `var.peering.role`
    (`requester` in the primary region, `accepter` in the secondary, wired by a Terragrunt `dependency` on
    the other region's leaf). PLAN 5.6 (hybrid connectivity) folded in here rather than a separate module:
    Site-to-Site VPN and a Direct Connect gateway association both attach to the *same* transit gateway; both
    off by default, module and docs only, no real peer to connect to. New `network/tgw-attachment` (spoke
    side, applied in a workload account): associates/propagates into exactly one route table (prod or
    nonprod, never both), optional central-egress default route.
  - **5.3** `network/inspection-egress`: three subnet tiers per AZ (tgw, firewall, public), NAT gateways one
    per AZ, AWS Network Firewall with a **stateful domain allow-list** (`STRICT_ORDER` +
    `drop_established`: anything not explicitly allowed is dropped once a connection is established, not a
    deny-list). Transit gateway attachment with appliance mode on (a flow keeps using the same firewall
    endpoint), into the "inspection" route table. Checkov: fixed properly (not skipped) — a KMS key for the
    firewall's rule groups/policy/firewall, `delete_protection`, and the VPC's own flow logs. `network/vpc`
    gets `egress_mode = "local-nat"` (default, unchanged) | `"central"` (no NAT gateways here at all,
    regardless of `enable_nat_gateway`). `FINOPS.md` has the cost comparison and an approximate crossover
    point (roughly 8–12 always-on spoke VPCs).
  - **5.4** `network/central-endpoints` (shared-services): one interface endpoint per service (ECR api/dkr,
    STS, SSM, SSM Messages, EC2 Messages, CloudWatch Logs, KMS, Secrets Manager, EKS), each with its **own**
    private hosted zone (the endpoint's own private DNS only resolves inside its own VPC, so it is turned
    off), shared with spoke accounts via `aws_route53_vpc_association_authorization` here — the spoke side
    (`aws_route53_zone_association`, in the spoke's own account) is **not built**, a documented follow-up.
    Gateway endpoints (S3, DynamoDB) are deliberately not included: they're free, and stay local to each VPC.
  - **5.5** `network/dns` (network-hub): inbound/outbound Resolver endpoints, a `FORWARD` rule per
    on-premises domain (RAM-shared with the Workloads OU, same pattern as 5.1/5.2), resolver query logging,
    public hosted zones with an NS-delegated subdomain per workload account. Checkov: the VPC's own flow logs
    fixed properly; **DNSSEC signing and public-zone query logging inline-skipped with a reason** — both need
    a resource in `us-east-1` specifically (an AWS requirement unrelated to this module's own region), which
    this pure module (no provider blocks) cannot create; a `us-east-1`-aliased-provider follow-up at the live
    layer, not built here.
  - **5.7** `network/vpc` + `governance/account-baseline`: `flow_log_destinations` (default `["cloudwatch"]`,
    unchanged behaviour) can add `"s3"` as well as or instead of CloudWatch, to `security/log-archive`'s
    `vpc_flow_logs` bucket. `exclude_public_subnets_from_account_bpa` (default off) excludes a VPC's own
    public subnets from the new account-wide `aws_vpc_block_public_access_options` in `account-baseline`
    (`block-bidirectional`, on by default). **The third 5.7 item (default security group with no rules) was
    already done** before this phase (`manage_default_security_group` with empty ingress/egress) — confirmed,
    not new work. The exclusion resource's `for_each` keys off the *configured* `var.public_subnets` index,
    not the upstream module's real subnet ids (unknown until apply in the same plan as VPC creation — the
    same class of limitation as 5.2's accepter, found the same way, by writing the test first).
  - **Checked (offline, across all seven):** `terraform fmt`, `terraform validate`, `terraform test` for
    every touched/new module (vpc 15, ipam 6, transit-gateway 14, tgw-attachment 6, inspection-egress 9,
    central-endpoints 7, dns 9, account-baseline 20 — 86 runs total); Checkov with the repo config on every
    touched/new module (0 failed everywhere; every skip has a stated, specific reason); `tflint` (found and
    fixed two real unused-declaration warnings: a stray data source in `network/dns`, and `network/ipam`'s
    `organization_id` was validated but never actually used anywhere — now tags every resource with it);
    `conftest verify` (66); `IAC_MODULES_LOCAL=1 terragrunt hcl validate --inputs` on every new/changed live
    leaf (network-hub × 2 regions, shared-services, management, workloads-dev/prod); the full repo-wide
    Checkov run (`run-checkov.sh`, 0 failed); pre-commit hooks on every commit.
  - **Not checked:** a real plan or apply anywhere (no AWS credentials used); the exact shape of
    `aws_networkfirewall_firewall.firewall_status[...].sync_states[...].attachment[0].endpoint_id` and the
    interface endpoint `dns_entry[0]` "is the regional one" assumption — both checked against the AWS
    provider's own schema (not guessed), neither against a real deployment; whether the log-archive
    `vpc_flow_logs` bucket policy really accepts Network Firewall's and the Resolver's S3/log deliveries (same
    underlying `delivery.logs.amazonaws.com` service, not tested end to end); the toolbox image (no Docker
    running here).
  - **Left for the owner to decide, in the PR description:** the DNSSEC/query-logging `us-east-1` follow-up
    (5.5); the spoke-side `aws_route53_zone_association` follow-up (5.4); when to flip a spoke's
    `egress_mode` to `"central"` and whether the FINOPS.md crossover estimate holds for the real fleet size;
    the CIDR sizes in `network/ipam`'s defaults and the three `172.16.0.0/20`-range VPC CIDRs picked for
    network-hub/shared-services (sized for a small platform, not verified against real usage); the starting
    `domain_allow_list` in `_envcommon/network/inspection-egress.hcl` (package/base-image registries only, a
    real list needs the owner's actual outbound needs).

- **2026-09-23 (Phase 5 follow-up / DX refactoring, branch `feat/p5-networking`)** — Reorganized live repositories to mirror the AWS Organization OU tree directly:
  - `foundation-live-repo`: grouped accounts under `security/` (`log-archive`, `security-tooling`) and `infrastructure/` (`network-hub`, `shared-services`), keeping `management` at the root.
  - `workloads-live-repo`: grouped accounts under `workloads/nonprod/workloads-dev` and `workloads/prod/workloads-prod`.
  - Updated `workloads-live-repo/scripts/generate_account_matrix.py` with `find_account_dir()` to resolve OU-nested account paths seamlessly with backwards compatibility.
  - Added unit test `test_working_directory_resolves_ou_nested_folders` in `test_generate_account_matrix.py` (all 11 unit tests passing).
  - Updated `workloads-live-repo/scripts/smoke-test.sh` default account path to `workloads/nonprod/workloads-dev`.
  - Updated `foundation-live-repo/management/env.hcl` module versions to point to released git tags (`organization-v2.1.0`, `bootstrap-stacksets-v2.1.0`, etc.).
  - Verified `check-account-registry.sh` passes cleanly (`✅ Every account.hcl matches the registry`).
  - Removed accidental orphaned `console,` scratch directory.

- **2026-09-28 (plan text only, branch `docs/p11-agentic-workflows`)** — Added Phase 11 (agentic IaC
  workflows and org adoption), ADR 11 in the 10.1 list, and Priority track order 7 (11.4, 11.6); the rest
  of Phase 11 is "later". No code changed and no AWS command was run. Reading the repo for it turned up four
  conflicts, now listed at the top of Phase 11: `main` has no branch protection or ruleset; the healer can
  push to `main` and has no attempt limit; the C1 MCP client most likely never reaches the Terraform MCP
  server; `trivy config` is still in pre-commit. Terraform MCP facts come from HashiCorp's README and
  reference page, read the same day.

- **2026-09-28 (Phases 7–11, branch `feat/p7-p11-dr-pipeline-observability-evidence-agentic`, from `main` after PR #69)** —
  The owner explicitly approved doing Phases 7–11 in one branch (this overrides rule 3 for this branch only). One commit
  per task group. No AWS command was run; no credentials were used.
  - **Phase 7 (7.1–7.5).** 7.1: `workloads-prod/eu-west-1/` with `region.hcl`, a VPC (`10.2.0.0/16`) and a warm-standby EKS
    (node group at 0); `terragrunt render` of the VPC leaf checked. No account-baseline in eu-west-1 (its account alias and
    password policy are global and would collide). 7.2: the Day-0 template got an optional `ReplicaRegion` (one-way state
    replication, deletes not copied; the replica region's stack creates only the bucket, gated by `CreateGlobalResources`,
    because the OIDC provider, boundary and CI roles are global IAM); `bootstrap-stacksets` got `secondary_region`
    (second instance, secondary region first). 7.3: new `data/aurora-postgres` (standalone / global_primary /
    global_secondary), new `data/backup`, and `storage/s3` optional replication. 7.4: new `network/route53-failover`.
    7.5: `DISASTER_RECOVERY.md` gained state-loss recovery, regional failover, RTO/RPO table and a quarterly game-day
    checklist. **Found:** it said state locking used DynamoDB; the repo uses S3 native lockfiles, now fixed.
    **Checked:** `terraform test` for every touched or new module (bootstrap-stacksets 12, aurora-postgres 7, backup 5,
    storage/s3 5, route53-failover 4), the bootstrap Python tests (16), `fmt`, `validate`, and the pre-commit gates
    (cfn-lint, Checkov, Trivy). **AWS docs check:** Secrets Manager-managed passwords are not supported for clusters in an
    Aurora global database (docs.aws.amazon.com, read 2026-09-28), so `global_primary` uses a write-only password and a
    module-owned secret without automatic rotation. **Not checked:** nothing was planned or applied against AWS; the
    Aurora engine version default (`16.6`) and instance class were not validated against what is offered in
    `eu-central-1` / `eu-west-1`; the RTO/RPO numbers are design targets, none measured; FINOPS prices are from memory.
    **Owner still needs to:** set `secondary_region` on the StackSets module and `ReplicaRegion` on the management stack
    when ready, then deploy the secondary region's stack first; fill real account IDs; run the first game day.
  - **10.8 (done early, so later entries land here).** The Execution log moved from `PLAN.md` to `docs/EXECUTION_LOG.md`;
    rule 8 and the link were updated. `PLAN.md` went from ~1,880 to ~1,360 lines.
  - **Phase 8.** 8.1: evaluated Terragrunt Stacks by running `stack generate` offline (Terragrunt 1.1.1); decision is *not
    yet*, in `docs/adr/0012-terragrunt-stacks.md` (model-written, owner to confirm). 8.3: `-lock-timeout=5m` in both
    `root.hcl` (checked with `terragrunt render` that it merges with the envcommon `terraform` block). 8.4: the security
    groups in dns, central-endpoints, data/postgres and aurora-postgres now use `name_prefix` + `create_before_destroy`
    (found: my own aurora SG had `create_before_destroy` with a fixed name, which would fail on replacement; fixed). IAM
    policies and the DB subnet groups were left alone on purpose (fixed names, and the boundary policy is protected by
    name). CloudFront has no ACM resource (the cert is an input). New `docs/runbooks/blue-green-infra.md`. 8.5: PR plans
    cover only affected units (`plan_scope.py`, tested); shared code or any non-PR run plans everything. 8.6: the plan job
    saves binary plans with `--out-dir` plus a SHA256SUMS manifest (push to main only, 1 day); the apply job downloads,
    verifies and applies exactly those, with no fallback to a fresh plan. 8.7: `generate_account_matrix.py --per-region`;
    drift detection now runs and opens one issue per account/region. 8.8: **found** `live_env_dir()` in `iac_agent.py` and
    `generate-module.sh` still used the pre-OU layout (`workloads-live-repo/workloads-<env>`); both fixed and tested, and the
    prompts and `AGENTS.md` paths and required tags updated. 8.10 (partly): `policy-library-repo/POLICIES.md` (one catalog)
    and a CI check that fails when a Rego rule is not listed (tested).
    **8.9 step 5 and the 8.10 pruning (done after the owner said so):** `trivy config` is gone from the static-analysis
    action, the plan job, `terragrunt.yml`, pre-commit, `make security` and the agent's validation ladder, and `.trivyignore`
    is deleted; Trivy now only scans the toolbox image. Rego: `deny_public_s3` removed (every case maps to `CKV_AWS_53-56`, `70`);
    `require_encryption` trimmed to EC2 instance and launch template volumes; `deny_open_ingress` trimmed to the datastore ports;
    `deny_iam_wildcards` kept. Checkov IDs checked with `checkov --list`. **Finding:** the cases I kept have no Checkov cover,
    because `.checkov.yaml` skips `CKV_AWS_8` repo-wide under the comment "Detailed monitoring", but `CKV_AWS_8` is EBS
    encryption for instances and launch configurations, so Checkov does not enforce it here (comment is wrong, owner to
    decide). `conftest verify`: 48 tests pass. 8.2 (Digger) is not built: the plan marks it low priority and the ADR is the
    owner's. The Rego `exceptions` data file is not built. **Also found:** the CI step "Terraform Validate" uses
    `find iac-modules-repo -maxdepth 2 -name main.tf`, but module files are at depth 3, so it has never validated anything.
    **Not checked:** none of the workflow changes ran on GitHub (no actionlint available; YAML parses). The `--out-dir` /
    `--json-out-dir` / `--filter=[origin/<base>...HEAD]` flags were read from `terragrunt run --help` (1.1.1), but the
    toolbox image pins Terragrunt 1.0.3, and I could not confirm the flags exist there or the file names `--json-out-dir`
    writes (the workflow globs `*.json` for that reason). **First PR and first main run must be watched.** The Checkov IDs in
    `POLICIES.md` are from memory and marked unverified.
  - **Phase 9.** 9.1: new `observability/oam` (sink / link, optional Managed Prometheus workspace; Managed Grafana is *not* built,
    it needs Identity Center wiring), a new `observability` account in the registry (placeholder id `000000000007`, `ci = false`)
    with a sink leaf, and an optional `observability_sink_arn` link in `governance/account-baseline`. 9.2: new
    `governance/billing` (CUR 2.0 Data Export to a locked-down bucket, Cost Anomaly Detection per OU plus one by service,
    cost allocation tags, Athena showback query in the README) with a management leaf; the Data Exports resource has no
    `region` argument, so the module needs a `us-east-1` provider alias, which the leaf generates. `FINOPS.md` got a
    landing-zone cost section that says plainly **nothing is measured yet** and how to measure it. 9.3: new
    `observability/guardrail-signals` (six CloudTrail-based alarms and one dashboard; alarms in management, dashboard in
    observability through OAM), `docs/SLO.md` (3 measurable SLOs, 1 not measurable yet), and the agent's error-budget gate now
    prefers a measured value (`.agents/metrics/platform_slo.json`, at most 8 days old) over the static YAML, with the env
    override still first. 9.4: `.agents/scripts/delivery_metrics.py` (lead time, deployment frequency, change failure rate,
    drift MTTR, the `ai-generated` split for 11.5, cost per verified agent change) and a weekly workflow.
    **Checked:** `terraform test` for oam (6), account-baseline (23), billing (6), guardrail-signals (5); `terragrunt render` of
    the four new leaves; 27 agent tests (13 new, offline). **Not checked:** nothing was applied; `delivery_metrics.py` was tested
    on synthetic data only and never run against the real `gh` API (field names come from `gh` help, unverified here); the
    metric filter patterns were not run against real CloudTrail events; the CUR 2.0 column names in the Athena example are
    unverified; FINOPS prices are from memory. **Not covered:** CloudTrail delivery failures (no metric exists) and "drift open
    over 7 days" as an alarm (reported in the weekly summary instead). **Found:** none of `terraform validate`, and the
    `moved`/alias behaviour of a root module with `configuration_aliases`, run in CI (see the Phase 8 note on the no-op
    validate step): `governance/billing` would fail a standalone `terraform validate`.
  - **Phase 10 (what a model can do; the rest is the owner's).** 10.2: a Mermaid diagram (OUs, accounts, CI identity chain, log
    and finding flows, network hub, second region) at the top of `docs/ARCHITECTURE.md` and in the README. **Not done:** the exported
    PNG (no `mmdc` available), and the Mermaid was **not rendered**, so the syntax is unchecked. 10.4: README rewritten to lead
    with the multi-account foundation, a "what is real and what is not" table (nothing in the new organization applied,
    no measured numbers, `COMPLIANCE.md` not written), the agent section below it; the old claim that the platform was "deployed to a real AWS
    account and torn down" is now attributed to the old single account. 10.6: `CONTRIBUTING.md` (add a module in 30 minutes, what a
    good PR looks like, the review checklist the auditor uses); the auditor prompt was **stale** (it listed the Rego rules removed in
    8.10) and is fixed, as was a standing guardrail in `PLAN.md` that still named `.trivyignore`. 10.7: partly, in
    `docs/migrations/2026-single-to-multi-account.md`: only what the log supports (no state moved, no downtime, five things found while
    working), with a checklist for the parts that need real accounts. 10.8: done earlier.
    **Left for the owner, on purpose:** 10.1 (the ADRs, in your own words; `0012-terragrunt-stacks.md` is the only new one and is marked
    as a model-written proposal), 10.3 (the walkthrough you say out loud), 10.5 (failure drills need a sandbox and real postmortems),
    and the rest of 10.7.
  - **Phase 11 (11.1-11.6; 11.7 is the owner's story card).** 11.1: `make verify-module MODULE=<category/name>`
    (`workloads-live-repo/scripts/verify_module.py`): fmt, init, validate, tflint, checkov, terraform test, and conftest on a plan JSON
    from `<module>/examples/basic`, offline with fake keys set in the environment only. Output: one line per failure
    (`<tool> <check-id> <file>:<line>`), a status per step, `--json`, exit code 1 on failure; a step that cannot run says SKIPPED with a
    reason, never a silent pass. **Checked first, as the plan asked:** with `.checkov.yaml`, `-d <module>` *narrows* the scan (6 checks on
    `data/backup`, identical to a run without the config), it does not add to the `directory:` list. **Done-when, checked:** a clean module
    (`storage/s3`) passes all 7 steps with no AWS credentials; a copy with public access turned off fails with `CKV_AWS_53`, `CKV_AWS_56`
    and its own test. Only `storage/s3` and `network/route53-failover` have `examples/basic` so far; every other module reports conftest as
    SKIPPED. **Found:** the new example made Checkov evaluate `route53-failover`'s alias records and flag `CKV2_AWS_23`, which would have
    failed the next commit and CI; fixed with an inline skip and a reason.
    11.2: the rules are in `.agents/AGENTS.md` ("Local agent guardrails"); `.claude/settings.json` + `.agents/hooks/guard.py` implement them
    (block apply/destroy/import/force-unlock/state edits and `run --all` without a read-only command, through `cd`, `bash -c`, `sudo`, `xargs`
    and `make`; block edits to the checks, the policy library and the hooks; run `verify-module` after a module edit; stop after 3 failures;
    `guard.py reset` clears it). 22 tests found and fixed **four bugs in my own guard** (a flag value read as the command, a quoted string cut
    in half, and a `lstrip` that removed the leading dot of `.checkov.yaml` so the protection never matched). **Seen live:** once installed,
    the hook refused my own test command in this session. **Known limits:** the splitting ignores quotes, so a command that only *mentions* a
    blocked command inside quotes is refused (I hit it twice); the fix is written up but the hook files are protected, so a human applies it
    (`guard_quote_aware_split.md` in the session scratchpad; not tested by me). The "broken edit gets the summary back" half of the done-when
    was covered by tests, not observed in a real session.
    11.3: `.agents/mcp/README.md` (evaluation notes for ADR 11), the compose file (pinned tag, `127.0.0.1` only, no `TFE_TOKEN`, the unpinned
    community Terragrunt image removed) and `mcp_client.py` (handshake, session id, SSE, the real tool names) with a fake-server test.
    **Not run against the real server** (needs a Docker pull); the argument names of the two tools are from memory; `--toolsets=registry` is a
    `TODO(owner)` because the container's command line was not verified. **Finding:** the old client sent no `initialize` and called tools that
    are not in HashiCorp's list, so it most likely always used the GitHub fallback (a reading of the code, not a measurement). ADR 11 is the
    owner's.
    11.4: `docs/AGENT_AUTONOMY.md` (a row per agent, levels per environment, enforcing controls that exist, seven known gaps). **Confirmed today:**
    `main` has no protection and no rulesets. **Fixed while writing it:** the healer (`healer_guards.py`, 9 tests) now refuses `main`, refuses a
    branch without an open PR, stops after 3 healer commits and refuses protected paths, and puts back the branch's own `.agents/` before
    committing; the ChatOps workflow ran for **any commenter on a public repo with LLM secrets and a write token**, and now needs OWNER, MEMBER or
    COLLABORATOR, and lost an unused `id-token: write`. **Not run on GitHub.**
    11.5: PRs from ChatOps and healer pushes get the `ai-generated` label; `delivery_metrics.py` splits every number by it with sample sizes,
    prices CI minutes per verified agent change (LLM tokens are not recorded yet, so that part says so). Synthetic data only.
    11.6: `docs/AGENTIC_ADOPTION.md`, marked as a model-written draft; the legal points are a checklist for legal, the DPO and the works council.
    **Left for the owner:** 11.7 (story card), rewriting 11.6, ADR 11, and applying the guard fix.
