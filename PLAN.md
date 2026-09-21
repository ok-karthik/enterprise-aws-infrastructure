# PLAN.md — Enterprise Multi-Account AWS Platform Roadmap

Goal: grow this repo from a single-account Terragrunt demo into the cloud foundation a scaleup
actually runs: **multi-account, multi-region, multiple OUs, least-privilege access, SOC2 /
ISO 27001-ready security, hub-and-spoke networking and WAF**. It works hand in hand with
[`internal-developer-platform`](https://github.com/ok-karthik/internal-developer-platform)
(IDP), which uses the modules published from here.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done

---

## How to use this plan (read first if you are an implementing agent)

1. Read [`.agents/AGENTS.md`](.agents/AGENTS.md) first. It explains the Terragrunt include
   chain, the governance gates and the conventions this plan builds on.
2. **Do the phases in order.** Phase 0 fixes bugs on the current layout. Phase 1 renames and
   splits folders, and every later phase uses the new paths. Don't start Phase 2 while
   Phase 1 is half done.
3. **One phase (or one numbered task group) per branch and PR.** Branch names look like
   `feat/p2-account-factory`. Use Conventional Commits with the module name as the scope
   (`feat(vpc): ...`), because release-please builds per-module versions from them.
4. **Implementing agents never run `apply`.** No `terraform apply`, `terragrunt apply` or
   `destroy`, and never bypass the prod approval gate. Checking your work means `fmt`,
   `validate` (with `-backend=false` where there are no credentials), `tflint`, `conftest`,
   `checkov`, `trivy` and the unit tests. The repo owner applies the tasks marked 🟢 / 🟡 in
   the *Priority track* below to the real sandbox accounts, by hand.
5. **Never make up real AWS account IDs, org IDs, SSO instance ARNs or IdP details.** Use the
   placeholders defined in task 2.1 and mark them `# TODO(owner): real value`. The human fills
   them in.
6. **When a path or behaviour changes, update the docs in the same PR:** `.agents/AGENTS.md`,
   `README.md`, `docs/ARCHITECTURE.md`, `docs/CICD.md`, `GOVERNANCE.md`, the CODEOWNERS files
   and the agent prompts in `.agents/prompts/`.
7. Every new module gets `README.md`, `variables.tf` (with descriptions and validation),
   `outputs.tf` and `versions.tf`. It also gets an entry in `release-please-config.json` and
   `.release-please-manifest.json` (start at `1.0.0`), and a Rego or Checkov rule for any new
   guardrail it depends on.
8. When a task is done, tick its box and add a dated line to the **Execution log** at the
   bottom saying what changed and how you checked it. If you skip something or it doesn't
   pass, say so there. Don't mark it done.

### Standing guardrails (apply to every phase, including the IaC agent in `.agents/`)

- Never auto-push to `main`, never apply, never bypass the prod manual-approval gate.
- Every change, human or agent, has to pass the OPA/Checkov/Trivy/Infracost gates as they
  are. Suppressions go in `.checkov.yaml` / `.trivyignore`, each with a comment saying why.
- Modules stay pure: no `provider` or `backend` blocks, and nothing environment-specific.
- Security settings live in the modules (fail closed), not only in CI checks.
- Diff-only, single-module-scoped generation stays the default for the IaC agent.

---

## Priority track (job search: 2026-09-21 → mid-October)

This repo is also the main evidence for Senior/Staff Platform/Cloud interviews. The job-ad
data (467 Senior+ infra ads, 131 Staff/Lead/Principal, Germany, Aug–Sep 2026) says two things:

- **Named landing-zone tools are rarely required.** Multi-account/landing zone is in 6.6% of
  ads, SOC2 6.6%, ISO 27001 9.6%, WAF 2%, Transit Gateway 2%, Terragrunt 1.9%. **The broad
  themes behind them are everywhere:** security 62%, AWS 53%, Terraform 49%, networking 38%
  (45% at Staff), compliance/audit 36%, cost 34–39%, HA/resilience 28–34%. So this work mostly
  pays off in **system-design rounds** ("design AWS for a company going from 3 to 50 teams"),
  not as keyword matches on a CV.
- **What separates Staff from Senior is writing and trade-offs, not tools:** design
  docs/ADRs 22% → **37%**, mentoring 34% → **50%**. Every phase therefore ends with an ADR
  (Phase 10).

**So do the work in this order.** It's the smallest slice that gives you real, working,
demonstrable infrastructure and interview stories. Everything after it can wait until after
the offers.

| Order | Tasks | Why first |
|---|---|---|
| 1 | Phase 0 (all) | Small, and every item is a "here's a real bug I found and fixed" story |
| 2 | Phase 1 (**time-box: one day**, one PR) | The repo layout is the first thing a reviewer sees |
| 3 | 2.0–2.6 + 2.8 with **real accounts** | Makes it actually multi-account. Creating accounts is free |
| 4 | 3.1, 3.2, 3.6 | Identity Center + permission sets (learning-plan Sprint 1) |
| 5 | 4.1, 4.2, 4.4, 4.5, 4.6 (SCPs + RCPs only), 4.9 | Guardrails + detection + auto-remediation (learning-plan Sprint 2) |
| 6 | 10.1–10.4 | ADRs, architecture diagram, system-design walkthrough, stories |
| later | Phases 5–9, rest of 3/4 | Deeper interview topics; mostly 🔴 plan-only because of cost |

**Target: orders 1–6 done by Sunday 2026-09-27.** See the day-by-day schedule below.

### Parallel learning track (owner) — 2026-09-21 → 2026-09-27

Two tracks run side by side. **The implementing model writes the code** for the Priority
track, one PR per phase. **The owner learns the same topic in the AWS console first**, then
reviews that PR and applies the 🟢/🟡 parts. That way every PR review happens right after
you've built the same thing by hand.

**The loop for each topic:**
1. **Build it in the console** to see the moving parts.
2. **Read the module** that does the same thing and match each click to a resource.
3. **Import what you clicked** (`import {}` block or `terraform import`) and get `plan` to
   show no changes. Interviewers ask about imports.
4. **Break it on purpose** (a bad SCP on Policy-Staging, a removed permission) and write
   down what happened in `docs/runbooks/`. That write-up becomes your interview story.

**Who owns what, so console clicks and Terraform don't fight:**
- Organizations and Identity Center exist **only once per org**. Whatever you click there
  gets **imported** into Terraform the same day (step 3). Don't leave it half-managed.
- Free console experiments go in a **Sandbox OU account that Terraform doesn't manage**.
- Accounts managed by Terraform: change them through Terraform only. A console change
  there is drift, so treat it as a drill and run `plan`.

**Rules for writing:** the model writes modules, tests and docs. **You write, or rewrite in
your own words,** the ADRs (10.1) and the system-design walkthrough (10.3). If you can't
defend a choice out loud, the repo works against you in an interview.

| Day | Model builds (PR) | You: console + review + apply | Done when |
|---|---|---|---|
| **Mon 21** | Phase 0, then 2.0a (CloudFormation bootstrap) | Tour Organizations. Create `log-archive` + `security-tooling` accounts (plus-addressed emails). Move the workload account into a NonProd OU. Enable StackSets trusted access. Review and merge Phase 0. **Don't run the Terragrunt `bootstrap.sh`**; run the 2.0a `bootstrap.sh` once its PR is merged | 2 new member accounts exist; Phase 0 CI green; `platform-bootstrap` stack up in management |
| **Tue 22** | Phase 1 (rename, one PR) | Identity Center: enable it, create a group and permission sets, assign them to the workload account, `aws sso login` from the CLI. Review and merge Phase 1 | Zero static keys; CLI works via SSO; new folder layout on `main` |
| **Wed 23** | 2.0b, 2.1–2.6, 2.8 | Import the accounts and OUs you created into `account-factory`. Apply `account-baseline` to `workloads-dev`. Set budgets. Write the state-key migration notes (10.7) | `plan` shows no changes for the org; budget alerts arrive by email |
| **Thu 24** | 3.1, 3.2, 3.6 | Write a region-deny SCP in the console on Policy-Staging, trigger `AccessDenied`, then delete it. Import Identity Center into Terraform. Apply the permission sets | You can explain SCP vs IAM vs boundary cold; Access Analyzer is on |
| **Fri 25** | 4.1, 4.2, 4.4, 4.5, 4.6 (SCP/RCP), 4.9 | Console: GuardDuty + Security Hub + Config with delegated admin to `security-tooling`, and the org trail to `log-archive`. Apply. Open 0.0.0.0/0:22 and time the auto-remediation | Findings visible in `security-tooling`; remediation time < 30s written down |
| **Sat 26** | — (fix-ups from review) | **You:** ADRs 1–5 (10.1), architecture diagram (10.2), failure drills 1–2 (10.5) | 5 ADRs + diagram committed; 2 runbooks |
| **Sun 27** | README draft (10.4) | **You:** system-design walkthrough (10.3), finish the README, rehearse it out loud twice. Set a reminder on day 25 of the free trials to disable GuardDuty/Security Hub/Macie or check their cost | You can give the 20-minute answer without notes |

**Protect the job-application block every day.** Applications are due by **30 Sep**, and they
matter more than any row in this table. If a day slips, cut the model's scope first (move 3.6
or 4.6-RCP to "later"). Never cut applications or the ADR writing.

### Apply mode and sandbox cost (approximate eu-central-1 list prices, check before applying)

Legend: 🟢 apply and keep (≈ free / a few €) · 🟡 apply for a demo, capture evidence, then
destroy · 🔴 plan-only, never apply in the sandbox.

| Area | Mode | Cost note |
|---|---|---|
| Organizations, OUs, SCPs/RCPs/tag policies, new member accounts | 🟢 | Free. Use plus-addressed emails (`you+log-archive@…`) |
| IAM Identity Center, permission sets, Access Analyzer (external) | 🟢 | Free (unused-access analyzer is billed per role, so 🟡) |
| Org CloudTrail (management events) | 🟢 | First copy of management events is free; S3 storage is cents |
| GuardDuty, Security Hub, Inspector, Macie | 🟡 | 30-day free trials. Put a reminder at day 25 to disable them or check the cost |
| AWS Config + conformance packs | 🟡 | Billed per configuration item and rule evaluation; scope the recorder to key resource types |
| EventBridge + Lambda auto-remediation, Budgets | 🟢 | Free tier |
| KMS CMKs | 🟢 | ~$1/key/month, so keep the count small |
| VPC + NAT gateway, EKS | 🟡 | NAT ~$35/mo each, EKS control plane ~$73/mo |
| Transit Gateway | 🟡 | ~$36/mo per attachment + data |
| Network Firewall | 🔴 / short 🟡 | ~$290/mo per endpoint |
| WAF web ACL on one ALB | 🟡 | ~$5/ACL + $1/rule/month |
| Firewall Manager | 🔴 | ~$100 per policy per region per month |
| Shield Advanced | 🔴 | $3,000/month + 1-year commitment. Never |

---

## Target end state (what "done" looks like)

### Repository topology — `-repo` suffix convention

This follows the same convention as IDP [ADR 0010](https://github.com/ok-karthik/internal-developer-platform/blob/main/docs/adr/0010-tenant-repository-topology.md):
**a directory ending in `-repo` is a separate Git repository in a real company.** It only lives
here as a folder so the whole foundation can be read from one checkout. Drop the suffix and you
get the repo name (`iac-modules-repo/` → `<org>/iac-modules`). Repos are split by **who
approves changes and how much damage a bad change can do**, not by which tool they use.

```
enterprise-aws-infrastructure/
├── iac-modules-repo/          → <org>/iac-modules         versioned modules (release-please, <module>-vX.Y.Z)
├── foundation-live-repo/      → <org>/aws-foundation-live  landing zone: org, SCPs, identity, logging,
│   ├── _bootstrap/                                          security tooling, network hub (security + cloud-infra approve)
│   ├── _config/                                             account & region registry (source of truth)
│   ├── _envcommon/
│   ├── root.hcl
│   ├── management/  log-archive/  security-tooling/  network-hub/  shared-services/
├── workloads-live-repo/       → <org>/aws-workloads-live   platform stacks in workload accounts (platform team approves)
│   ├── _envcommon/
│   ├── root.hcl
│   └── <account>/<region>/<category>/<module>/terragrunt.hcl
├── policy-library-repo/       → <org>/policy-library       Rego policies + tests, used by every IaC pipeline
├── .github/                   → <org>/iac-pipelines        (stays at root: GitHub only runs workflows from here)
├── .agents/                   tooling, not a shipped repo
└── docs/
```

### AWS Organization

```
Root
├── Security OU          log-archive, security-tooling (delegated admin for security services)
├── Infrastructure OU    network-hub, shared-services (ECR, CI runners, IPAM, ACK hub cluster)
├── Workloads OU
│   ├── Prod OU          <team|domain>-prod accounts
│   └── NonProd OU       <team|domain>-dev / -staging accounts
├── Sandbox OU           budget-capped experimentation, auto-cleanup
├── Policy-Staging OU    test SCPs/RCPs here before rolling them out wider
└── Suspended OU         deny-all; accounts waiting to be closed
Management account: Organizations, billing, Identity Center only. No workloads, ever.
```

This follows the AWS SRA / *Organizing Your AWS Environment* layout. The management account
sits at the root, not in an OU (SCPs never apply to it anyway). CI/CD and shared services go
in **Infrastructure**, not Security: the Security OU gets the strictest SCPs and is owned by
the security team. OUs exist to apply policy, so don't mirror the org chart. Terraform
manages OUs and accounts (2.3, 2.4). CloudFormation is used only for the Day-0 bootstrap (2.0).

---

## Completed history (kept short; code comments refer to these IDs)

Phases A–D of the IaC Generation Agent are finished (2026-08-25 → 2026-08-27):
A1 policy digest · A2 semantic auditor gate · A3 Ollama provider · A4 eval harness ·
B1 drift-to-diff (`--reconcile`) · B2 ChatOps (`chatops_generator.yml`) · B3 Infracost gating ·
C1 MCP client · C2 multi-module `--graph` · D1 golden-path catalog · D2 Backstage templates ·
D3 platform API (`--serve`) · D4 health metrics · D5 SRE error-budget gating.
Per-module release-please tagging (old Phase G, first half) is also done: tags look like
`vpc-v1.0.0`, `eks-v1.0.0`, and so on.

The unfinished leftovers from the old plan have been moved here: old Phase E (Digger) → **8.2**,
old Phase F (lock timeout, create-before-destroy) → **8.3 / 8.4**, old Phase G second half
(Renovate tag-prefix rules) → **1.5**.

---

## Phase 0 — Fix what's wrong today (current layout, before any rename)

These are real security and correctness bugs. Each one is small. Do them on the current paths.

- [x] **0.1 `allowed_account_ids` checks nothing.** `infrastructure-live/root.hcl` sets
  `allowed_account_ids = [get_aws_account_id()]`, which compares the logged-in account with
  itself, so it always passes. Change it to use `local.account_vars.locals.aws_account_id`
  (from `account.hcl`). Do the same in `infrastructure-bootstrap/root.hcl`, which currently
  doesn't set `allowed_account_ids` at all. Keep using `get_aws_account_id()` only where the
  caller's account really is what you want (none today).
  *Done when:* running a leaf with credentials for the wrong account fails at provider init.

- [x] **0.2 GitHub OIDC role is too broad.**
  `infrastructure-bootstrap/dev/_global/security/github-oidc-role/terragrunt.hcl` trusts
  `repo:ok-karthik/enterprise-aws-infrastructure:*` and grants `AdministratorAccess`, so any
  branch or PR can become admin. Replace it with **two roles**:
  - `github-actions-plan`: trust `repo:<repo>:pull_request` and `repo:<repo>:ref:refs/heads/main`.
    Policy: `ReadOnlyAccess` plus read/write on the state bucket (state reads and lockfile
    writes) and nothing else.
  - `github-actions-apply`: trust only `repo:<repo>:environment:dev` / `environment:prod`
    (the GitHub Environments). Policy: `AdministratorAccess` for now, but with a
    **permissions boundary** that denies changes to the org, Identity Center, CloudTrail and
    the boundary itself. Phase 3.4 narrows this further.

  Update `.github/workflows/*.yml` so plan jobs use `vars.AWS_<ENV>_PLAN_ROLE_ARN` and apply
  jobs use `vars.AWS_<ENV>_APPLY_ROLE_ARN`. Document the new repo variables in `docs/CICD.md`.

- [x] **0.3 ACK spoke role can escalate to admin.** `governance/organization/main.tf` attaches
  `IAMFullAccess` and `AmazonS3FullAccess` to `ack-hub-controller-access`. Replace them with an
  inline, scoped policy:
  - S3 actions limited to buckets with a prefix variable (`var.ack_s3_bucket_prefix`).
  - IAM limited to `iam:CreateRole` / `PutRolePolicy` / `AttachRolePolicy` / `TagRole` /
    `DeleteRole*` / `PassRole` on `arn:aws:iam::*:role/${var.ack_role_path}*`, **with the
    condition `iam:PermissionsBoundary = <boundary ARN>`**.
  - Create that boundary policy in the same module (`ack-tenant-boundary`).

  Add a Rego rule (0.8) that fails any plan attaching `IAMFullAccess` or `AdministratorAccess`
  to a role whose name doesn't start with `github-actions-apply` or `break-glass`.

- [x] **0.4 The region SCP is hardcoded.** `deny_outside_eu_central_1` locks everything to
  `eu-central-1`. Replace it with `var.allowed_regions` (a list, validated to be non-empty) and
  build the `aws:RequestedRegion` condition from it. Use AWS's recommended list of exempt
  global services for `NotAction`. At minimum add `budgets:*`, `ce:*`, `globalaccelerator:*`,
  `health:*`, `trustedadvisor:*`, `waf:*`, `shield:*`, `account:*`, `billing:*`, `pricing:*`
  and `route53domains:*` to what is already there. Rename the resource to
  `deny_unapproved_regions`, and add a `moved {}` block so existing state isn't destroyed and
  recreated.

- [x] **0.5 EKS public endpoint must fail closed.** In `compute/eks/main.tf`, public access
  with no CIDRs currently falls back to `["0.0.0.0/0"]`. Add a `validation` (or a resource
  `precondition`) that errors when `cluster_endpoint_public_access = true` and
  `api_allowed_cidrs` is empty, and remove the `0.0.0.0/0` fallback.

- [x] **0.6 Standing admin for humans.** In `identity/human-access`, the `PlatformAdmin`
  permission set carries `AdministratorAccess`. Rename it to `PlatformEngineer` and attach
  `PowerUserAccess` plus an inline policy for the IAM actions it needs, limited to
  `role/platform/*`. Add a separate `BreakGlassAdmin` permission set (`AdministratorAccess`,
  1-hour session) that is **not assigned by default**. Phase 3.3 wires it to JIT approval.

- [x] **0.7 Single NAT gateway in prod.** `_envcommon/network/vpc.hcl` sets
  `single_nat_gateway = true` for every env, so one AZ outage takes down all prod egress.
  Move the setting to `env.hcl` (dev `true`, prod `false`, meaning one NAT per AZ) and read
  it from there. (Phase 5 removes the per-VPC NAT gateways completely.)

- [~] **0.8 More Rego policies** in `policies/terraform/`, each with a `_test.rego` file:
  - `deny_admin_attachments.rego` (from 0.3)
  - `deny_public_s3.rego`: no `aws_s3_bucket_public_access_block` with any flag `false`, and
    no bucket policy with `Principal: "*"` unless it has an `aws:PrincipalOrgID` condition.
  - `deny_open_ingress.rego`: no `0.0.0.0/0` or `::/0` ingress on 22, 3389, 5432, 3306,
    6379, 27017, 9200 or 443-to-private.
  - `deny_iam_wildcards.rego`: no `Action: "*"` together with `Resource: "*"` in any IAM
    policy document, outside an allow-list.
  - `require_encryption.rego`: RDS `storage_encrypted`, EBS `encrypted`, S3 SSE and SQS/SNS
    KMS must be set.
  - `require_tags.rego`: extend `require_service_tag.rego` to also require `Owner` and
    `DataClassification` (add both to the `default_tags` in `root.hcl`, reading them from
    `account.hcl`).

  *Done when:* `conftest verify --policy policies/terraform` passes and the existing plans
  still pass.

- [x] **0.9 Tag drift.** `_envcommon/governance/organization.hcl` sets
  `Project = "Infrastructure-Automation"`, but `root.hcl` default tags set
  `Project = "enterprise-aws-platform"`. Remove the override from the envcommon file and from
  the bootstrap OIDC role inputs.

---

## Phase 1 — Rename and split into `-repo` folders

A mostly mechanical move. **Rename-only commits must not change any behaviour.** Use `git mv`
so history follows the files. About 20 files mention `infrastructure-modules`, 23 mention
`infrastructure-live`, 12 mention `infrastructure-bootstrap` and 11 mention `policies/`, so
find them with `git grep`.

- [x] **1.1 Modules.** `git mv infrastructure-modules iac-modules-repo`. Update:
  - `release-please-config.json` package keys and `.release-please-manifest.json` keys
  - `.github/actions/static-analysis/action.yml`, `.pre-commit-config.yaml`, `Makefile`,
    `.checkov.yaml`, `.tflint.hcl` if it uses paths, `.github/CODEOWNERS`
  - `.agents/**` (prompts, `iac_agent.py`, catalog templates, backstage templates, tests)
  - `README.md`, `docs/*.md`, `.agents/AGENTS.md`, `.github/assets/visualizer.html`

  Add `iac-modules-repo/CODEOWNERS` whose header says:
  `# Becomes <org>/iac-modules — extract with: git subtree split -P iac-modules-repo -b iac-modules`.

- [x] **1.2 Split live into foundation and workloads.**
  - `foundation-live-repo/` gets `_global/governance/organization`, the whole
    `infrastructure-bootstrap/` (as `foundation-live-repo/_bootstrap/`, including
    `bootstrap.sh` and its README), and the `_envcommon/governance/` blueprint.
  - `workloads-live-repo/` gets `dev/`, `prod/`, `_envcommon/{compute,data,network}`,
    `scripts/`.
  - Each gets its own `root.hcl` (a duplicate is fine: separate repos can't share one) and
    its own `CODEOWNERS` header, like 1.1.
  - **State keys come from `path_relative_to_include()`**, so they stay the same as long as
    the path *below* the folder holding `root.hcl` stays the same. Check this: run
    `terragrunt render --format json` (or print `path_relative_to_include()`) for one leaf
    before and after, and confirm the `key` matches.

- [x] **1.3 Policies.** `git mv policies policy-library-repo` (keep `terraform/` inside).
  Update the conftest paths in CI, `smoke-test.sh`, the fmt commands, `iac_agent.py`
  (`build_policy_digest`) and the docs. Add a CODEOWNERS header.

- [x] **1.4 Pin modules by version so you can promote dev → prod.** Stop using
  `${get_repo_root()}/infrastructure-modules/...` in the `_envcommon` files:
  - Each account's `env.hcl` gets a `module_versions` map, for example
    `module_versions = { vpc = "vpc-v1.1.0", eks = "eks-v1.1.0" }`.
  - `_envcommon/<cat>/<mod>.hcl` builds the source from it:
    ```hcl
    locals {
      modules_local = get_env("IAC_MODULES_LOCAL", "") != ""
      version       = local.env_vars.locals.module_versions.vpc
      source        = local.modules_local ? "${get_repo_root()}/iac-modules-repo/network/vpc" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/network/vpc?ref=${local.version}"
    }
    ```
  - CI on PRs that change `iac-modules-repo/**` sets `IAC_MODULES_LOCAL=1`, so module
    changes are tested before they're released. Everything else uses the pinned tag.
  - **Tags created before the rename point to the old path.** Once 1.1 is merged, release
    every module (for example with a `feat(<module>): relocate to iac-modules-repo` commit per
    module) so tags exist at the new path. Only then set the pins. Until then, set
    `IAC_MODULES_LOCAL=1` in CI and write that down in the Execution log.
  - Promotion flow: bump the pin in `dev/env.hcl`, merge, check it; then open a second PR
    that bumps `prod/env.hcl`. Write this down in `docs/CICD.md`.

- [x] **1.5 Renovate tracks module tags (second half of old Phase G).** Add a
  `customManagers` regex entry for the `module_versions` maps in `env.hcl` (datasource
  `github-tags`, depName `ok-karthik/enterprise-aws-infrastructure`, with
  `extractVersionTemplate` removing the `<module>-v` prefix). Add one `packageRules` entry per
  module so a `vpc-v*` release only opens PRs that bump `vpc` pins. Add
  `"matchFileNames": ["**/dev/**"]` automerge = false, and group dev and prod bumps into
  **separate** PRs so the promotion order is kept.

- [x] **1.6 Fix scripts and CI for the new paths.** `smoke-test.sh` currently loops over
  `infrastructure-live/{dev,prod,staging}` and runs `validate` in dev. Change it to loop
  over both live repos, and keep the env and region name checks. Update
  `terragrunt.yml`, `reusable-terragrunt.yml`, `drift-detection.yml` and `destroy.yml`
  `working_directory` values. Update the fmt command in `.agents/AGENTS.md` §3 to cover
  `iac-modules-repo foundation-live-repo workloads-live-repo policy-library-repo`.

- [ ] **1.7 IDP repo follow-up** (in `../internal-developer-platform`, separate PR):
  - `1-platform-catalog/catalog.yaml` `capabilities_source_base` → `//iac-modules-repo`
  - `1-platform-catalog/per-tenant/infra/platform/team-iam.tf.tmpl` source path + new tag
  - `.agents/AGENTS.md` line ~218, `PLAN.md` examples
  - Bring the tree in line with its own ADR 0010: `3-tenant-workloads/tenant-a/{apps,infra,gitops}`
    → `3-tenant-repos/tenant-a/{workloads-repo,gitops-repo}` with `services/` / `platform/`
    naming as the ADR describes.

- [x] **1.8 ADR.** Add `docs/adr/0001-repository-topology.md` in this repo (create
  `docs/adr/`). It records the `-repo` convention, the reason for splitting foundation from
  workloads (different approvers and blast radius), why `.github/` stays at the root, and why
  bootstrap folds into foundation.

---

## Phase 2 — Real multi-account layout and account vending

> **Path note (Phase 1 is done):** the Phase 2 text below was written before the rename. Read
> `infrastructure-bootstrap/` as `foundation-live-repo/_bootstrap/`, `infrastructure-live/_global` as
> `foundation-live-repo/_global`, `infrastructure-live/{dev,prod}` as `workloads-live-repo/{dev,prod}`,
> `infrastructure-modules/` as `iac-modules-repo/` and `policies/` as `policy-library-repo/`.

Today `management`, `dev` and `prod` all use account `954171757349`. SCPs **do not apply to
the management account**, so none of the guardrails actually protect those workloads.
`954171757349` is the org's **management (payer) account** and it is **greenfield**: nothing
has been applied there yet, so there is no state or resource to migrate. Until
`workloads-dev` exists (2.1), don't apply the `dev` / `prod` live stacks into it.

- [x] **2.0 Day-0 bootstrap with CloudFormation (replaces the Terragrunt bootstrap).** *(2.0a deployed by the owner and merged (PR #49). 2.0b code done 2026-09-21 on branch `feat/p2-bootstrap-stacksets`; still open: the owner replaces the `ou-0000-00000000` placeholders in the live leaf and applies it.)*
  **May be done before Phase 1**: it only rewrites `infrastructure-bootstrap/`, and 1.2 moves
  that folder as-is. **Never run the Terragrunt `bootstrap.sh` in `954171757349`.**
  Why: `--backend-bootstrap` creates the state bucket outside any state, so nobody can plan or
  drift-check its settings. Terraform also can't reach a new account until that account has a
  bucket and a role. CloudFormation keeps its own state inside AWS. Service-managed StackSets
  deploy to every account that joins a targeted OU, with no human step. Decision (owner,
  2026-09-21): CloudFormation for Day-0, native Terraform for Organizations. **No Control Tower / AFT.**
  Two PRs: **2.0a** (management stack + cleanup, branch `feat/p2-cfn-bootstrap`) and **2.0b**
  (StackSets for member accounts, after 2.3 or after the OUs exist by hand).

  **2.0a-1 Template `infrastructure-bootstrap/cloudformation/account-bootstrap.yaml`.** One
  template for every account. Management deploys it as a plain stack; member accounts get it
  through 2.0b.
  - `Parameters`:
    - `GitHubRepo` (default `ok-karthik/enterprise-aws-infrastructure`, `AllowedPattern` `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`)
    - `GitHubEnvironment` (no default, `AllowedPattern` `^[a-z0-9-]+$`)
    - `AllowOrganizationsAdmin` (`"true"`/`"false"`, default `"false"`)
    - `NoncurrentVersionDays` (Number, default 90, min 30)
  - `Conditions`: `DenyOrganizations` = `AllowOrganizationsAdmin` is `"false"`.
  - `StateBucket` (`AWS::S3::Bucket`):
    - name `tg-state-${AWS::AccountId}-${AWS::Region}`, `DeletionPolicy` and `UpdateReplacePolicy` set to `Retain`
    - versioning on, SSE-S3 (`AES256`) with `BucketKeyEnabled`, all four Block Public Access flags on
    - `OwnershipControls: BucketOwnerEnforced`
    - lifecycle: noncurrent versions expire after `NoncurrentVersionDays`; abort incomplete multipart uploads after 7 days
    - The CMK and access logging come later (2.2, once log-archive exists). Put a Checkov
      `Metadata` skip on the bucket for the KMS and access-logging checks, each with a reason.
  - `StateBucketPolicy`: `DenyInsecureTransport` (`aws:SecureTransport = false`) and
    `DenyOldTls` (`s3:TlsVersion < 1.2`) on the bucket and `/*`.
  - `GitHubOidcProvider` (`AWS::IAM::OIDCProvider`): URL `https://token.actions.githubusercontent.com`,
    client ID `sts.amazonaws.com`. Check the current CloudFormation docs for whether
    `ThumbprintList` is still required. Leave it out if it isn't, because AWS no longer uses it
    for GitHub. If it is required, use GitHub's published thumbprints and say so in a comment.
  - `ApplyBoundary` (`AWS::IAM::ManagedPolicy`, name `github-actions-apply-boundary`). Port
    **every statement** from `infrastructure-bootstrap/dev/_global/security/github-actions-boundary/terragrunt.hcl`
    before deleting that file. Changes:
    - `DenyOrganizationAndIdentityCenter` splits in two. `organizations:*` + `account:*` only
      `!If DenyOrganizations`. The `sso:*`, `sso-directory:*` and `identitystore:*` deny is always on.
      (3.1 must add an `AllowIdentityCenterAdmin` switch before Identity Center is applied from CI.)
    - New, always on: `DenyOrgDestruction` on `organizations:DeleteOrganization`, `LeaveOrganization`,
      `CloseAccount` and `RemoveAccountFromOrganization`.
    - New, always on: `ProtectStateBucket` on `s3:DeleteBucket`, `s3:PutBucketPolicy`,
      `s3:DeleteBucketPolicy`, `s3:PutBucketVersioning`, `s3:PutEncryptionConfiguration`,
      `s3:PutBucketPublicAccessBlock` and `s3:PutLifecycleConfiguration` on the state bucket ARN.
    - New, always on: `ProtectBootstrapStack` on `cloudformation:DeleteStack`, `UpdateStack`,
      `UpdateTerminationProtection`, `SetStackPolicy`, `CreateChangeSet` and `ExecuteChangeSet` on
      `arn:aws:cloudformation:*:${AWS::AccountId}:stack/platform-bootstrap/*` and `.../stack/StackSet-bootstrap-*`.
    - Build ARNs with `!Sub` and fixed names, not `!Ref` to itself (that would be a circular reference).
  - `PlanRole` (`github-actions-plan`, max session 3600): trust exactly as today (`aud` =
    `sts.amazonaws.com`; `sub` in `repo:${GitHubRepo}:pull_request`, `repo:${GitHubRepo}:ref:refs/heads/main`).
    `ReadOnlyAccess` plus the three inline statements from today's plan role: bucket list,
    state read, and put/delete on `*.tflock` only.
  - `ApplyRole` (`github-actions-apply`, max session 3600): `sub` =
    `repo:${GitHubRepo}:environment:${GitHubEnvironment}` (`StringEquals`, no wildcard),
    `AdministratorAccess`, `PermissionsBoundary: !Ref ApplyBoundary`.
  - `Outputs`: `StateBucketName`, `PlanRoleArn`, `ApplyRoleArn`, `OidcProviderArn`. **No
    `Export`s**, because an export locks the resource against changes.
  - No tags in the template. Tags come from the stack (`--tags`) and propagate: `Project`,
    `ManagedBy=CloudFormation`, `Owner` and `DataClassification`, read from `account.hcl`.
  - `infrastructure-bootstrap/cloudformation/stack-policy.json`: deny `Update:Replace` and
    `Update:Delete` on `LogicalResourceId/StateBucket`, `LogicalResourceId/GitHubOidcProvider`
    and `LogicalResourceId/ApplyBoundary`; allow `Update:*` on everything else.

  **2.0a-2 One-time commands (owner only; the agent never runs `aws` commands).**
  `bootstrap.sh` runs steps 2–4, and the README lists them for a manual run. Use an SSO
  profile for `954171757349`, **never the shell's default profile**.
  ```bash
  export AWS_PROFILE=<management-admin-profile> AWS_REGION=eu-central-1
  # 1. Preflight: must print 954171757349
  aws sts get-caller-identity --query Account --output text

  # 2. Organization (all features) + StackSets trusted access. Safe to run again.
  aws organizations describe-organization >/dev/null 2>&1 \
    || aws organizations create-organization --feature-set ALL
  aws cloudformation activate-organizations-access
  aws cloudformation describe-organizations-access          # expect "Status": "ENABLED"

  # 3. Deploy through a reviewed change set
  aws cloudformation validate-template \
    --template-body file://infrastructure-bootstrap/cloudformation/account-bootstrap.yaml
  aws cloudformation deploy \
    --stack-name platform-bootstrap \
    --template-file infrastructure-bootstrap/cloudformation/account-bootstrap.yaml \
    --parameter-overrides GitHubEnvironment=management AllowOrganizationsAdmin=true \
    --capabilities CAPABILITY_NAMED_IAM \
    --tags Project=enterprise-aws-platform ManagedBy=CloudFormation Owner=platform-team DataClassification=internal \
    --no-execute-changeset
  aws cloudformation describe-change-set --stack-name platform-bootstrap --change-set-name <name printed above>
  aws cloudformation execute-change-set  --stack-name platform-bootstrap --change-set-name <name>
  aws cloudformation wait stack-create-complete --stack-name platform-bootstrap   # stack-update-complete on later runs

  # 4. Lock it down and read the outputs
  aws cloudformation update-termination-protection --enable-termination-protection --stack-name platform-bootstrap
  aws cloudformation set-stack-policy --stack-name platform-bootstrap \
    --stack-policy-body file://infrastructure-bootstrap/cloudformation/stack-policy.json
  aws cloudformation describe-stacks --stack-name platform-bootstrap --query 'Stacks[0].Outputs'
  ```
  GitHub wiring (printed by the script, not run by it):
  - Create the `management` Environment with the owner as required reviewer.
  - Set `AWS_REGION`, and set `AWS_DEV_PLAN_ROLE_ARN` / `AWS_PROD_PLAN_ROLE_ARN` to the
    management plan role. Plans are read-only, so they can stay pointed at management until
    `workloads-dev` exists.
  - **Leave `AWS_DEV_APPLY_ROLE_ARN` / `AWS_PROD_APPLY_ROLE_ARN` unset.** The management apply
    role only trusts `environment:management`, so dev/prod apply jobs can't deploy workloads
    into management. This is intended; say so in `docs/CICD.md`. CI for `_global` (the org leaf)
    comes with 2.6.

  **2.0a-3 Clean up `infrastructure-bootstrap/`.**
  - **Delete:** `root.hcl` and all of `dev/` (`account.hcl`, `env.hcl`, `_global/region.hcl`,
    the four `_global/security/*/terragrunt.hcl` units and the `.terraform.lock.hcl`). Port
    the boundary and plan-role statements into the template first (2.0a-1).
  - **Add:** `cloudformation/account-bootstrap.yaml` and `cloudformation/stack-policy.json`.
  - **Rewrite `bootstrap.sh`:**
    - Read the expected account ID, `owner` and `data_classification` from
      `infrastructure-live/_global/account.hcl` (the management leaf; one source of truth).
    - Keep the preflight: no credentials → exit 1; wrong account → exit 1, nothing changed.
    - Run steps 2–4 above. Show the change set and ask before executing it (`--yes` skips the prompt).
    - Detect "stack already exists" and wait for update-complete instead of create-complete. Treat
      "no changes" as success.
    - Print the GitHub wiring.
    - Must pass `shellcheck`.
  - **Rewrite `README.md`:** what the stack creates, the commands above, the gotchas below,
    and "how to change the template later" (edit, then run `bootstrap.sh`, which shows a change set).
  - `infrastructure-live/root.hcl`: bucket becomes `tg-state-${local.account_id}-${local.aws_region}`.
    Remove `s3_bucket_tags` and the auto-create comment. Terragrunt no longer creates the
    bucket, and **no command in the repo may pass `--backend-bootstrap`** (grep for it).
    Nothing was applied, so no state moves.
  - Remove `infrastructure-bootstrap` from the `terraform fmt` lists: `Makefile` `FMT_DIRS`,
    `.pre-commit-config.yaml`, `.github/actions/static-analysis/action.yml`,
    `infrastructure-live/scripts/smoke-test.sh` and `.agents/scripts/iac_agent.py`.
    Keep it in `.checkov.yaml` (Checkov scans CloudFormation).
  - Add `cfn-lint` to pre-commit and to the static-analysis action, run on
    `infrastructure-bootstrap/cloudformation/*.yaml`.
  - Update the docs: `.agents/AGENTS.md` (lines ~14, 73 and 149; line 14 also wrongly mentions
    a DynamoDB lock), `README.md` (~41, ~113), `docs/ARCHITECTURE.md` (~26),
    `docs/CICD.md` (~28, role variables and the `management` Environment) and the
    `.github/assets/visualizer.html` comment.
  - Gotchas for the README:
    - An account can have only one GitHub OIDC provider, so the stack fails if one already exists.
    - The bucket and OIDC provider are retained, or protected by the stack policy. A deleted
      and recreated stack fails on the bucket name, so import the bucket by hand.
    - `environment:dev` can apply to **any** NonProd account (per-account Environments come with 2.6).
  - Checks: `cfn-lint`, `checkov -f` on the template (no failures without a reasoned skip),
    `shellcheck` + `bash -n` on `bootstrap.sh`, a stubbed-`aws` run of the preflight (no
    credentials → exit 1; wrong account → exit 1), `terragrunt render` showing the new bucket
    name, and a repo-wide `git grep` showing no stale `infrastructure-bootstrap/dev` or
    `--backend-bootstrap` references.
  *Done when (2.0a):* the owner has deployed `platform-bootstrap` with termination protection
  and the stack policy, and a PR's plan job assumes `github-actions-plan` and passes.

  **2.0b StackSets for member accounts.**
  - New module `governance/bootstrap-stacksets`:
    - `aws_cloudformation_stack_set` with `permission_model = "SERVICE_MANAGED"`,
      `auto_deployment { enabled = true, retain_stacks_on_account_removal = true }`,
      `capabilities = ["CAPABILITY_NAMED_IAM"]` and `operation_preferences` (max concurrent 25%,
      failure tolerance 0).
    - `aws_cloudformation_stack_set_instance` per target, with `deployment_targets { organizational_unit_ids = [...] }`,
      in the primary region only.
    - The template body is an **input** (`var.template_body`). The live leaf passes
      `file("${get_repo_root()}/infrastructure-bootstrap/cloudformation/account-bootstrap.yaml")`,
      so the module stays pure.
  - One stack set per GitHub Environment, because the apply trust subject differs:
    `bootstrap-nonprod` (NonProd OU → `dev`), `bootstrap-prod` (Prod OU → `prod`) and
    `bootstrap-core` (Security + Infrastructure OUs → `core`). Sandbox and Suspended are not targeted.
  - Apply from `.../management/_global/governance/bootstrap-stacksets`. OU IDs come from the
    organization module outputs (2.3). Until then, pass the IDs of the OUs created by hand and
    import them later.
  - Gotcha: an account that moves between OUs targeted by different stack sets has its stack
    deleted and created again, and the create fails on the retained bucket name. Accounts
    shouldn't move between Prod and NonProd.
  *Done when (2.0b):* a new account created in NonProd gets its bucket and roles with no
  manual step, and a PR can run `plan` against it.

- [x] **2.1 Account and region registry.** `foundation-live-repo/_config/accounts.hcl`:
  ```hcl
  locals {
    accounts = {
      management       = { id = "000000000000", ou = "Root",           env = "global",  email = "aws+management@example.com" }
      log-archive      = { id = "000000000001", ou = "Security",       env = "global",  email = "aws+log-archive@example.com" }
      security-tooling = { id = "000000000002", ou = "Security",       env = "global",  email = "aws+security@example.com" }
      network-hub      = { id = "000000000003", ou = "Infrastructure", env = "global",  email = "aws+network@example.com" }
      shared-services  = { id = "000000000004", ou = "Infrastructure", env = "global",  email = "aws+shared@example.com" }
      workloads-dev    = { id = "000000000005", ou = "NonProd",        env = "dev",     email = "aws+workloads-dev@example.com" }
      workloads-prod   = { id = "000000000006", ou = "Prod",           env = "prod",    email = "aws+workloads-prod@example.com" }
    }
  }
  ```
  Placeholder IDs are marked `# TODO(owner)`. `management` keeps the real `954171757349`.
  The owner already has a second real account (the "Account A" workload account from the
  learning plan). It becomes `workloads-dev`, and the owner fills in its ID. `log-archive` and
  `security-tooling` should become **real accounts too**, created by 2.4. Member accounts are
  free, and they're what make the SCP and delegated-admin stories true. `network-hub`,
  `shared-services` and `workloads-prod` can stay placeholders until they're needed.
  Add `_config/regions.hcl` with `primary_region = "eu-central-1"`,
  `secondary_region = "eu-west-1"` and `allowed_regions_by_ou = { ... }`. The SCP in 0.4 and
  all per-region leaves read from this file.
  Add `scripts/check-account-registry.sh`, which fails CI if any `account.hcl` in either live
  repo has an ID that isn't in the registry. (In real life the workloads repo would get this
  file from a pinned foundation release.)

- [x] **2.2 Account-first layout and `root.hcl` rework** (both live repos):
  - Layout: `<account-name>/<region|_global>/<category>/<module>/terragrunt.hcl`.
    `<account-name>/account.hcl` holds `aws_account_id`, `account_name`, `ou`, `env`, `owner`
    and `data_classification`. `env.hcl` stays at account level (one account = one env).
  - `root.hcl` reads `env` from `account.hcl` instead of `split(path)[0]`.
  - No `assume_role` in the provider. Each CI job logs in over OIDC directly to the
    `github-actions-plan` / `-apply` role of the one account it targets (2.0, 2.6). Humans use
    an SSO profile per account. `allowed_account_ids` stays as the guard.
  - The state bucket stays per account per region (`tg-state-<id>-<region>`, created by the
    2.0 stack). Later it gets KMS CMK encryption, access logging to log-archive and
    replication to `secondary_region`. Add those to the 2.0 template, not to Terraform.
  - Move `workloads-live-repo/dev` → `workloads-dev/` and `prod` → `workloads-prod/`. **This
    changes state keys.** Write `scripts/migrate-state-keys.sh`, which prints (dry-run by
    default) the `aws s3 mv` / `terragrunt state` commands needed for each unit. The human
    runs it. The agent does not.
  - Update the `smoke-test.sh` checks: env comes from `account.hcl` and must be in
    `dev|staging|prod|global`, and the region must be in `regions.hcl`.

- [x] **2.3 `governance/organization` module v2.** Replace the two hardcoded OUs with a
  `var.organizational_units` map (nested: Workloads → Prod/NonProd) that creates Security,
  Infrastructure, Workloads{Prod,NonProd}, Sandbox, Policy-Staging and Suspended. Output a
  map of OU name → id. Enable the needed org service access principals and
  `enabled_policy_types` (SCP, RCP, TAG_POLICY, BACKUP_POLICY, DECLARATIVE_POLICY_EC2). Move
  the ACK hub/spoke resources into their own module, `identity/ack-cross-account`, because
  they are applied per account, not in management.

- [x] **2.4 New module `governance/account-factory`.** It takes the registry and creates
  `aws_organizations_account` resources (with `close_on_deletion = false`,
  `lifecycle { prevent_destroy = true }`, placed in the right OU, and IAM billing access
  allowed). Apply it from `foundation-live-repo/management/_global/governance/account-factory`.

- [x] **2.5 New module `governance/account-baseline`**, applied to **every** account (a stack
  per account in the live repos, or a `terragrunt.stack.hcl`, see 8.1). The state bucket and
  the CI roles are **not** in here: they come from the 2.0 StackSet, because this module needs
  them before it can run. It creates:
  - The IAM permissions boundary `platform-workload-boundary`, which every role that
    Terraform, ACK or tenants create must use.
  - An account alias, the IAM password policy, S3 account-level Block Public Access, EBS
    encryption by default, and IMDSv2 as the account default.
  - A KMS CMK per data class (`general`, `confidential`) with rotation on.
  - The discovery parameters (see 2.7).

- [x] **2.6 CI identity: direct OIDC per account.** Every account has its own GitHub OIDC
  provider and `github-actions-plan` / `-apply` roles from 2.0. There is no shared-services hub
  role and no role chaining. The blast radius stays one account, and the pipeline doesn't depend
  on a shared-services account existing. Workflows run a matrix over accounts (generated from
  `_config/accounts.hcl` by a small script step) instead of fixed `dev`/`prod` jobs. Each job
  builds its role ARN from the account ID (`arn:aws:iam::<id>:role/github-actions-plan`), so
  the per-env `AWS_<ENV>_*_ROLE_ARN` repo variables go away. GitHub Environments: `dev`,
  `prod` (manual approval kept), `core` and `management` (required reviewers). Optional later:
  one Environment per account, with the StackSet parameter set per OU target.
  *Considered and rejected:* one OIDC provider in shared-services that assumes into
  `terraform-*` roles in each account. It's fewer providers, but it adds a hop and a
  high-value hub role, and it needs shared-services before anything else can deploy.

- [x] **2.7 Discovery contract gets an account dimension.** SSM parameters live inside one
  account. Once the VPC sits in network-hub and is shared via RAM (Phase 5), tenants can't
  read it from their own account. So `account-baseline` (or a `discovery-publisher` module
  applied per workload account) writes the **same parameter names** into every workload
  account: `/platform/${env}/${region}/vpc/id`, `.../vpc/database_subnets`,
  `.../eks/cluster_name`, `.../eks/oidc_provider_arn` and `.../ack/cross_account_role_arn`.
  Values come from dependency outputs. Add `/platform/${env}/${region}/account/{id,ou}` and
  `.../kms/{general,confidential}_key_arn`. Document the full contract in
  `docs/DISCOVERY_CONTRACT.md`, and update the table in `.agents/AGENTS.md` §2.3.

- [x] **2.8 Budgets from day one** (moved forward from 9.2 because it also protects the
  sandbox bill): `account-baseline` creates an AWS Budget per account (monthly amount from
  `accounts.hcl`, alerts at 50/80/100% actual and 100% forecast, sent to SNS/email) and a Cost
  Anomaly Detection monitor. In the management account, set a low org-wide budget
  (e.g. €50) during the job-search period.

---

## Phase 3 — Identity and least privilege

- [ ] **3.1 Identity Center with an external IdP.** New module
  `identity/identity-center` (applied in management, or in a delegated admin account if you
  choose to delegate). It creates groups (or reads SCIM-synced groups via
  `data "aws_identitystore_group"`), a permission-set catalog, and **account assignments
  driven by a map of OU → group → permission set**, expanded to accounts using the registry.
  The IdP itself (Okta / Entra ID / Google) is set up by hand. Document the SCIM steps in
  `docs/IDENTITY.md`.

- [ ] **3.2 Permission-set catalog** (in `identity/human-access`, or merged into 3.1):
  `ReadOnly`, `Developer` (a customer-managed policy + the `platform-workload-boundary`, only
  in NonProd/Sandbox; read-only in Prod), `PlatformEngineer` (from 0.6), `SecurityAudit`
  (`SecurityAudit` + `ViewOnlyAccess`), `Billing`, `BreakGlassAdmin`. Sessions: 1h for
  admin-level sets, 8h otherwise. Use ABAC session tags (`team`, `cost_center`) from the IdP
  where they make sense.

- [ ] **3.3 Just-in-time elevated access.** Document and scaffold AWS TEAM (Temporary
  Elevated Access Management), or a SaaS equivalent, for `BreakGlassAdmin` and
  prod-`PlatformEngineer`. Requests need approval, are time-limited and are logged to
  log-archive. At minimum, deliver `docs/BREAK_GLASS.md` with the runbook and an
  EventBridge rule plus SNS alert for any `BreakGlassAdmin` sign-in.

- [ ] **3.4 Narrow the apply role.** Replace `AdministratorAccess` on `github-actions-apply` (2.0 template) with
  the managed policies for the services actually used, plus a boundary that denies:
  organizations, account, sso, cloudtrail stop/delete, changes to guardduty, config and
  securityhub, and edits to `platform-*` roles and the boundary itself.

- [ ] **3.5 Centralized root access management.** Enable the org feature that removes root
  credentials from member accounts (`aws_iam_organizations_features` with
  `RootCredentialsManagement` and `RootSessions`). Document how to do a privileged root task.

- [ ] **3.6 Access Analyzer.** An org-level analyzer for external access **and** unused
  access, delegated to security-tooling. Findings go to Security Hub.

---

## Phase 4 — Security baseline and compliance (SOC2 CC6/CC7/CC8, ISO 27001 Annex A)

- [ ] **4.1 `security/log-archive` module** (log-archive account): S3 buckets for CloudTrail,
  Config, VPC flow logs, WAF logs, ALB/CloudFront access logs and state-bucket access logs.
  **Object Lock in compliance mode** (retention set by a variable, default 400 days for
  CloudTrail), a KMS CMK, lifecycle to Glacier, and bucket policies that allow only the
  service principals + `aws:SourceOrgID`.

- [ ] **4.2 `security/org-cloudtrail` module** (management): an organization trail across
  all regions, log file validation, KMS, delivery to log-archive, S3 data events for buckets
  tagged `DataClassification=confidential`, and CloudTrail Lake (optional flag).

- [ ] **4.3 `security/org-config` module:** delegated admin = security-tooling, an org
  recorder in every allowed region, an aggregator in security-tooling, and conformance packs
  (Operational Best Practices for CIS AWS Foundations and NIST 800-53, plus the SOC2 pack
  where one exists).

- [ ] **4.4 `security/threat-detection` module** (security-tooling as delegated admin,
  auto-enable for the org): GuardDuty (S3, EKS audit + runtime, RDS, Malware Protection,
  Lambda), Security Hub (FSBP + CIS v3 standards, cross-region aggregation to
  `primary_region`), Inspector v2 (EC2, ECR, Lambda), Macie (auto-discovery on accounts
  tagged confidential), Detective (optional flag).

- [ ] **4.5 Alerting pipeline.** EventBridge rules in security-tooling for Security Hub
  findings of HIGH/CRITICAL, GuardDuty findings of severity ≥ 7, root sign-in, BreakGlass
  sign-in and SCP changes. Send them to SNS, then to Slack/PagerDuty (webhook URLs come from
  Secrets Manager and are never committed). Add an optional Firehose → SIEM export.

- [ ] **4.6 Full org policy set** (in `governance/organization` or a new
  `governance/org-policies` module). Test on the Policy-Staging OU first:
  - **SCPs:** deny root user actions; deny `LeaveOrganization`; region allow-list per OU
    (from 0.4 and `regions.hcl`); deny disabling CloudTrail/Config/GuardDuty/SecurityHub/
    AccessAnalyzer/Macie; deny `iam:CreateUser` / `CreateAccessKey` (except the break-glass
    path); protect `platform-*` and `github-actions-*` roles, the GitHub OIDC provider and
    `tg-state-*` buckets from changes by any principal except the StackSets service role
    (`AWSServiceRoleForCloudFormationStackSetsOrgMember`) and break-glass; require IMDSv2 on `ec2:RunInstances`; deny creating
    roles without the permissions boundary (`iam:PermissionsBoundary` condition); Sandbox
    only: deny large instance families and Reserved Instance / Savings Plan purchases;
    Suspended: deny all.
  - **RCPs (data perimeter):** deny S3/KMS/SQS/Secrets Manager/STS access from principals
    outside the org (`aws:PrincipalOrgID`, with exceptions for AWS service principals), and
    enforce `aws:SecureTransport`.
  - **Declarative policies (EC2):** VPC Block Public Access (ingress), block public AMI and
    EBS snapshot sharing, IMDSv2 defaults.
  - **Tag policies:** allowed values for `Environment`, and `Owner`, `CostCenter`,
    `DataClassification` enforced on taggable resources.
  - **Backup policies:** daily and weekly plans for resources tagged `backup=true`, a vault
    in each account with Vault Lock, and a copy to a central backup account or to
    `secondary_region`.

  Keep every policy document as a `.json.tftpl` file with a unit test (a Rego test that
  runs against the rendered JSON, or a `terraform test` in the module).

- [ ] **4.7 Compliance mapping.** `docs/COMPLIANCE.md` is a table with the columns
  *Control (SOC2 TSC / ISO 27001:2022 Annex A)* → *How it's met (module/policy)* →
  *Evidence (where an auditor finds it)*. Add a short **EU / Germany section**, because
  German employers ask for these (GDPR 12.6% of Senior+ infra ads; BSI C5 / NIS2 / DORA 7% of
  Staff ads):
  - **GDPR data residency:** the region allow-list SCP (0.4) + RCP data perimeter (4.6) +
    Macie. Say which regions hold personal data.
  - **BSI C5:** a short note on which C5 areas the same controls cover (logging, identity,
    crypto, operations). Don't make up criteria IDs.
  - **NIS2 / DORA:** incident detection and reporting (4.5), backup and resilience testing
    (4.6, 7.5), third-party/ICT risk (supply-chain gates in CI).

  Cover at least these controls: Cover at least: CC6.1/6.2/6.3/6.6/6.7/6.8,
  CC7.1/7.2/7.3, CC8.1, A.5.15-5.18 (access), A.8.2 (privileged access), A.8.15/8.16
  (logging/monitoring), A.8.20-8.22 (network security/segregation), A.8.24 (cryptography),
  A.8.32 (change management), A.8.13 (backup). Point to existing evidence as well: PR
  approvals + CODEOWNERS + saved plan artifacts (CC8.1). Increase plan artifact retention in
  `reusable-terragrunt.yml` to 400 days, or copy the plans to log-archive.

- [ ] **4.8 Audit Manager** (optional flag in `threat-detection`, or its own module): turn on
  the SOC 2 and ISO 27001 frameworks in security-tooling so evidence is collected
  continuously.

- [ ] **4.9 Auto-remediation** (security-tooling, with a small Python Lambda in
  `iac-modules-repo/security/auto-remediation/src/`): an EventBridge rule on the
  `AuthorizeSecurityGroupIngress` CloudTrail event, and on the matching Config rule
  (`restricted-ssh` / `vpc-sg-open-only-to-authorized-ports`). The Lambda assumes a narrow
  `security-remediation` role in the member account (created by `account-baseline`), removes
  any `0.0.0.0/0` or `::/0` rule on 22/3389, tags the SG `remediated-by=auto`, and posts to the
  4.5 SNS topic. Needs Python unit tests (moto or stubbed boto3), type hints, and `mypy`
  clean. **Measure it:** write the time from the rule being created to its removal
  (target < 30s) into `docs/runbooks/auto-remediation.md`. That number is the interview story
  (learning-plan Sprint 2).

---

## Phase 5 — Networking (hub and spoke)

- [ ] **5.1 `network/ipam` module** (network-hub): an org-wide IPAM with a top-level pool,
  regional pools, and env pools per region (prod / nonprod), shared through RAM with the
  Workloads OU. The `network/vpc` module gets `ipv4_ipam_pool_id` +
  `ipv4_netmask_length` as an alternative to `var.cidr` (keep `cidr` for backwards
  compatibility). Validate that exactly one of the two is set.

- [ ] **5.2 `network/transit-gateway` module** (network-hub, per region): TGW with default
  association and propagation **off**, and route tables `prod`, `nonprod`, `shared` and
  `inspection`. Share it through RAM with the Workloads and Infrastructure OUs. Add a
  cross-region peering attachment between `primary_region` and `secondary_region`. Spoke VPCs
  attach with a `network/tgw-attachment` module applied in the workload account (the
  acceptance side is in network-hub). Prod and nonprod can't route to each other.

- [ ] **5.3 `network/inspection-egress` module** (network-hub, per region): a central egress
  VPC with NAT gateways (one per AZ) and AWS Network Firewall. The firewall policy has a
  stateful domain allow-list (a variable), Suricata rules, and alert + flow logs sent to
  log-archive. TGW appliance mode is on. Spoke VPCs lose their NAT gateways and send
  `0.0.0.0/0` to the TGW (a `vpc` module flag: `egress_mode = "local-nat" | "central"`).
  Document the cost comparison in `FINOPS.md`.

- [ ] **5.4 `network/central-endpoints` module:** interface endpoints (ECR api/dkr, STS, SSM,
  ssmmessages, ec2messages, logs, KMS, Secrets Manager, EKS) in a shared-endpoints VPC.
  Route 53 private hosted zones are associated with spoke VPCs so they resolve centrally.
  Gateway endpoints (S3, DynamoDB) stay in each VPC (they're free).

- [ ] **5.5 `network/dns` module:** Route 53 Resolver inbound and outbound endpoints in
  network-hub, forwarding rules for on-prem domains shared through RAM, and resolver query
  logging to log-archive. Public hosted zones stay in network-hub, with delegated subdomains
  per workload account.

- [ ] **5.6 Hybrid connectivity (optional flags):** Site-to-Site VPN attached to the TGW, and
  a Direct Connect gateway association. Module and docs only; there's no real peer to
  connect to.

- [ ] **5.7 VPC module hardening:** flow logs to the log-archive bucket (instead of, or as
  well as, CloudWatch), the default security group with no rules, and the VPC Block Public
  Access exclusion only for designated ingress subnets.

---

## Phase 6 — Edge security and WAF

- [ ] **6.1 `security/firewall-manager` module** (security-tooling as FMS admin, which needs
  delegation from management): WAFv2 policies applied automatically to all ALBs, API
  Gateways and CloudFront distributions in chosen OUs. The baseline rule groups are AWS
  Managed Common, KnownBadInputs, Amazon IP reputation, Anonymous IP list, Bot Control
  (prod, count mode first) and a rate-based rule. Per-OU overrides go in variables. It also
  covers FMS security-group policies (audit for overly open SGs) and Network Firewall
  policies when Phase 5.3 is present.

- [ ] **6.2 WAF logging:** WAF logs → Firehose (`aws-waf-logs-*`) → log-archive S3, with
  redaction of the `authorization` and `cookie` fields.

- [ ] **6.3 `edge/cloudfront` module** (a capability module for tenants too): Origin Access
  Control for S3 origins, minimum `TLSv1.2_2021`, an ACM cert (in us-east-1 through a provider
  alias the caller passes in), standard-logging to log-archive, a WAF web ACL association and
  a response-headers policy (HSTS, CSP placeholder).

- [ ] **6.4 Shield Advanced** (optional flag, prod OU only): subscription, protections on
  CloudFront/ALB/Route 53 zones, and proactive engagement contacts as variables. Put the cost
  warning in `FINOPS.md`.

---

## Phase 7 — Multi-region and disaster recovery

- [ ] **7.1** Add `secondary_region` leaves for the workload VPC and EKS (in
  `workloads-prod/eu-west-1/...`), driven by `regions.hcl`. The region SCP allow-list includes
  it.
- [ ] **7.2** State buckets replicated to `secondary_region` (from 2.5). Document the
  recovery steps if the primary region's state is lost in `DISASTER_RECOVERY.md`.
- [ ] **7.3** Data tier: an `aurora-global` option in `data/postgres` (or a new
  `data/aurora-postgres` module), S3 cross-region replication in `storage/s3` (optional
  flag), and cross-region copies of AWS Backup recovery points (from 4.6).
- [ ] **7.4** Failover: a `network/route53-failover` module (health checks + failover
  records). Mention Route 53 ARC for prod.
- [ ] **7.5** Update `DISASTER_RECOVERY.md` with RTO/RPO per tier and a quarterly game-day
  checklist (ISO 27001 A.5.30 evidence).

---

## Phase 8 — Pipeline at scale (includes the old Phases E and F)

- [ ] **8.1 Terragrunt Stacks.** Look at `terragrunt.stack.hcl` for `account-baseline` and the
  standard workload stack (vpc + eks + discovery). The aim is to cut boilerplate in the leaf
  folders. Write down the decision (use it or not, and why) in an ADR.
- [ ] **8.2 Orchestrator: Digger (old Phase E) vs Atlantis vs Spacelift/env0.** *Low priority:
  these tools appear in < 1% of ads. Writing the ADR (10.1 #9) is worth more than building
  it.* Write an ADR first. Default recommendation: **Digger**, because it runs inside GitHub Actions (no server
  to host), is open source, and works with the existing OIDC roles. If you pick Digger:
  - `digger.yml` at the root, with projects generated per Terragrunt unit across both live
    repos (`generate_projects` with a Terragrunt parsing config).
  - `.github/workflows/digger.yml` for `digger plan` / `digger apply` comments. Apply only
    after approval, with the prod Environment gate still in place.
  - Locking: use whatever Digger's docs currently recommend. Only add a DynamoDB lock table in
    `_bootstrap` if Digger requires one (Terraform state already uses S3 native locking via
    `use_lockfile`).
  - Hook the existing gates (tflint, trivy, checkov, conftest, infracost) into Digger's
    workflow steps.
  - Update `.agents/scripts/healer_runner.py` to read logs from failed Digger runs.
- [ ] **8.3 Lock contention (old Phase F).** Add `-lock-timeout=5m` to plan and apply in CI
  (`extra_arguments` in `root.hcl` for plan, apply and destroy). The account-first layout
  already splits state by account, region and component, so an app PR won't block on
  network state.
- [ ] **8.4 Safe replacements (old Phase F).** Add `create_before_destroy` wherever it's safe
  (launch templates, security groups created with `name_prefix`, ACM certs, IAM policies
  attached to roles). Write `docs/runbooks/blue-green-infra.md` for changes that can't be
  done in place (VPC CIDR, EKS major version upgrade, TGW changes): build the new one next to
  the old one, cut traffic over, then remove the old one.
- [ ] **8.5 Plan only what changed.** PR plans run only for units affected by the diff
  (Terragrunt's queue filtering, or Digger's project detection), with a full run on a
  schedule.
- [ ] **8.6 Apply exactly what was reviewed.** The apply job uses the saved `tfplan.bin`
  artifact from the approved plan run (checking a checksum) instead of planning again.
- [ ] **8.7 Drift detection per account and region**, not per env: the matrix comes from the
  registry, with one GitHub Issue per account/region.
- [ ] **8.8 Keep the IaC agent in sync:** update `.agents/prompts/*.md`, the catalog
  templates, the eval fixtures and the tests for the new paths and the account-first layout.
  `python3 .agents/scripts/iac_agent_eval.py` and `python3 -m unittest discover -s .agents/tests`
  must pass.

---

## Phase 9 — Observability and FinOps across accounts

- [ ] **9.1** An observability account (Infrastructure OU) with CloudWatch cross-account
  observability (OAM sink there, links from every workload account through
  `account-baseline`). Amazon Managed Prometheus / Grafana workspace as an optional flag.
- [ ] **9.2** Billing: a CUR 2.0 / Data Exports bucket in management (or a billing account),
  Cost Anomaly Detection monitors per OU (per-account budgets are already in 2.8), and a
  showback view by `CostCenter` tag. Update `FINOPS.md` with the measured cost of the landing
  zone itself (per-account baseline cost, NAT per VPC vs central egress).
- [ ] **9.3 SLOs for the foundation itself** (observability is in 64% of Senior+ infra ads;
  SLOs in 21% of Staff ads). CloudWatch alarms and one dashboard in the observability account
  for "the guardrails are working" signals: CloudTrail delivery failures, Config recorder
  stopped, GuardDuty/Security Hub disabled in any account, root or BreakGlass sign-in, drift
  issues open for more than 7 days. Define 3–4 platform SLOs in `docs/SLO.md` (for example
  "99% of PR plans finish in < 10 min", "drift fixed within 5 working days", "new account
  vended in < 1 hour") and connect them to `.agents/sre/error_budgets.yaml`, so the
  error-budget gate uses real numbers instead of static ones.
- [ ] **9.4 Delivery metrics for infra changes.** A small script (Python, run in CI) that
  computes lead time, deployment frequency, change failure rate (failed or reverted applies)
  and drift MTTR from GitHub Actions and issue history. It writes a weekly summary into the
  drift-detection issue or into `.agents/metrics/`.

---

## Phase 10 — Evidence and Staff-level signal (runs alongside every phase)

The job data says Staff roles are chosen on design docs, trade-offs and mentoring, not on
tools. This phase turns the work into things an interviewer or hiring manager can see.
Everything goes under `docs/`.

- [ ] **10.1 One ADR per phase** in `docs/adr/`, half a page each, always in the same three
  parts: *Context · Decision · What I chose against and what it cost.* Required ADRs:
  1. Repository topology and the `-repo` convention (1.8)
  2. Terraform-native Organizations vs Control Tower/AFT
  3. State bucket per account vs one central state account, and Day-0 in CloudFormation
     StackSets vs Terraform/Terragrunt (2.0)
  4. Identity Center + JIT access vs standing admin
  5. SCP vs RCP vs permissions boundary: which layer blocks what
  6. Transit Gateway vs VPC peering vs Cloud WAN
  7. Central egress + Network Firewall vs NAT per VPC (with the cost numbers from 9.2)
  8. Firewall Manager vs WAF per ALB (cost vs consistency)
  9. Digger vs Atlantis vs a paid Terraform CI service (8.2)
  10. Terragrunt vs plain Terraform/OpenTofu. Terragrunt appears in ~2% of ads and Terraform
      in ~49%, so write down why Terragrunt is still worth it here, and keep modules usable
      from plain Terraform.
- [ ] **10.2 Architecture diagram**: one diagram (Mermaid in `docs/ARCHITECTURE.md`, plus an
  exported PNG for the README) showing OUs → accounts → CI identity chain → log and finding
  flows → network hub. It goes at the top of `README.md`.
- [ ] **10.3 `docs/SYSTEM_DESIGN_WALKTHROUGH.md`**: the answer to "design the AWS foundation
  for a scaleup going from 3 to 50 teams", written to be said out loud in 20 minutes. Stage 1
  (one account) → stage 2 (this repo's layout) → stage 3 (multi-region, many teams). At each
  stage, cover what breaks first and what you'd add next. Link to the ADRs.
- [ ] **10.4 README rewrite for a 90-second read**: what it is, the diagram, what's actually
  applied vs plan-only (be honest, using the 🟢/🟡/🔴 table), the security controls with
  links to `COMPLIANCE.md`, and how it connects to `internal-developer-platform`.
- [ ] **10.5 Failure drills → runbooks + postmortems** (incident/on-call is in 46% of ads).
  Run at least three drills in the sandbox and write each one up in
  `docs/runbooks/` with a short blameless postmortem. Examples: break the OIDC trust (CI can't
  assume its role), cause a state lock conflict, delete a VPC endpoint (private subnet loses
  access to SSM/ECR), apply a bad SCP to the Policy-Staging OU and roll it back. Link to the
  EKS drills in the IDP repo.
- [ ] **10.6 Contributor guide** (the mentoring signal): `CONTRIBUTING.md` with "how to add a
  module in 30 minutes", a walkthrough of a good PR, and the review checklist the Policy
  Auditor agent uses. This shows how others would work in the repo, not just how you work.
- [ ] **10.7 The single-account → multi-account migration as a story** (migration is in ~15%
  of ads): record what 2.2's state-key migration actually took (units moved, downtime, what
  went wrong) in `docs/migrations/2026-single-to-multi-account.md`.

---

## Changes needed in `internal-developer-platform` (separate PRs in that repo)

- [ ] **IDP-1** Module source paths and pins (task 1.7).
- [ ] **IDP-2** `1-platform-catalog/per-tenant/infra/platform/providers.tf.tmpl`: the provider
  assumes a role into the **tenant's own account** (from `tenant.yaml` → account per env), not
  a shared account. The IDP scaffolder asks for or looks up the tenant account.
- [ ] **IDP-3** `4-platform-engineering/1-cloud-foundation/README.md`: update the contract
  table to point to `docs/DISCOVERY_CONTRACT.md` here, and note that the parameters are
  published into every workload account (2.7).
- [ ] **IDP-4** ACK controllers run in the hub cluster (shared-services) and assume spoke
  roles from `identity/ack-cross-account`. Update the IAM docs for the scoped permissions and
  the boundary from 0.3.
- [ ] **IDP-5** Tenant Terraform CI pulls policies from `policy-library-repo` (a pinned
  conftest bundle) so tenant infra is checked against the same Rego rules.

---

## Execution log

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
  - **Still open in Phase 2:** the owner steps above (real ids and emails, imports, `ci = true` for management, branch protection). **1.7** (IDP repo) and the **2.0b "Done when"** are also still open.
