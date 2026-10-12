# Enterprise IaC Platform & SRE Agent Registry

This document serves as the comprehensive single source of truth for AI agents (Claude Code, Antigravity, custom scripts) and engineers building, auditing, and maintaining the **Enterprise AWS Platform (Terragrunt)**.

---

## 1. What This Repository Is

A multi-environment AWS Infrastructure-as-Code platform built with **Terragrunt + Terraform**. There is no application code — the "product" is HCL config, reusable Terraform modules, OPA/Rego policies, and the GitHub Actions pipeline that plans/applies them. An autonomous Python "healer" agent auto-remediates failed CI runs, and an on-demand IaC Platform Agent scaffolds and reconciles compliant modules.

### Infrastructure Layout
A directory ending in `-repo` is a separate Git repository in a real company (see `docs/adr/0001-repository-topology.md`); here they live side by side so the whole foundation can be read from one checkout.

*   `/iac-modules-repo/`: Custom reusable Terraform modules, versioned per module (`<module>-vX.Y.Z`). Pure `.tf`, no environment specifics, no provider blocks.
*   `/iac-live-repo/`: All live Terragrunt stacks, one folder per account: `iac-live-repo/<account>/<region or _global>/<stack>/terragrunt.hcl` (management, security, network, observability and the workload accounts `workloads-dev` / `workloads-prod`). One `root.hcl`, the account registry in `_config/`, and `_bootstrap/`. Ownership per account folder is set in `.github/CODEOWNERS`.
*   `/scripts/`: Smoke test, module/stack generator, account matrix, cost gate and the other CI helpers (with `tests/`).
*   `/iac-live-repo/_bootstrap/`: Day-0 **CloudFormation** stack `platform-bootstrap` (`cloudformation/account-bootstrap.yaml`: S3 state bucket, GitHub OIDC provider, `github-actions-plan` / `github-actions-apply` roles + permissions boundary) and the `bootstrap.sh` that deploys it. Run once by a human in the management account; member accounts get it through StackSets (PLAN 2.0b). Terragrunt never creates the state bucket: **no command may pass `--backend-bootstrap`**.
*   `/policy-library-repo/terraform/`: Rego-based OPA compliance rules enforced against Terraform plan JSON.
*   `/iac-agents-repo/`: Autonomous IaC platform agent, CI healer, golden-path catalog, SRE policies, and tests.

---

## 2. Module Boundary: Tenant-Facing Capabilities vs. Internal Foundation

Per **ADR 0011** and **ADR 0012**, all AWS Terraform previously located in `internal-developer-platform` is owned and published from this repository. Because `iac-modules-repo/` uses domain-first grouping (`data/`, `storage/`, `identity/`, `compute/`, `network/`, `governance/`), the architectural boundary between **tenant-facing capabilities** and **internal foundation stacks** is defined below:

### 1. Tenant-Facing Capability Modules (Consumed via IDP Catalog)
Consumed externally by the `ok-karthik/internal-developer-platform` catalog and scaffolder engines via Git URL + pinned semantic version tag:
```
git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/<category>/<module>?ref=<module>-vX.Y.Z
```

| Module Path | Capability Name | Public Release Tag | Contract & Guardrails |
|---|---|---|---|
| `iac-modules-repo/data/postgres` | `postgres` | `postgres-v1.0.0` | KMS encryption, Secrets Manager password rotation, private subnets only, automated backups |
| `iac-modules-repo/storage/s3` | `s3` | `s3-v1.0.0` | S3 Block Public Access, AES256 server-side encryption, versioning enabled |
| `iac-modules-repo/identity/workload-iam` | `iam` | `workload-iam-v1.0.0` | Documented interface stub for workload pod identity / IRSA role vending |

### 2. Platform Foundation Modules (Internal to this Repository)
Applied and maintained directly by this platform via Terragrunt stacks (`iac-live-repo/<account>/<region>/<stack>`, for example `iac-live-repo/workloads-dev/...` and `iac-live-repo/management/_global/`):

| Module Path | Scope | Release Tag | Purpose |
|---|---|---|---|
| `iac-modules-repo/network/vpc` | Regional | `vpc-v1.0.0` | Multi-AZ VPC, flow logs (CloudWatch and/or S3), deny-all default NACL, no-rules default SG, private & database subnets. `ipv4_ipam_pool_id`/`ipv4_netmask_length` as an alternative to a literal `cidr` (PLAN 5.1); `egress_mode = "local-nat"` (own NAT gateways) or `"central"` (PLAN 5.3, no NAT here, routes through the transit gateway instead) |
| `iac-modules-repo/network/ipam` | Global (network-hub) | `ipam-v1.0.0` | Org-wide IPAM (PLAN 5.1): a top-level pool, one regional pool per region, prod/nonprod env pools per region, the env pools RAM-shared with the Workloads OU |
| `iac-modules-repo/network/transit-gateway` | Regional (network-hub) | `transit-gateway-v1.0.0` | Hub-and-spoke Transit Gateway (PLAN 5.2): default route association/propagation off, prod/nonprod/shared/inspection route tables, the transit gateway itself RAM-shared with Workloads and Infrastructure. Explicit spoke-attachment acceptance (`accept_vpc_attachments`, off through the transit gateway's first apply). Optional Site-to-Site VPN / Direct Connect gateway association (PLAN 5.6) |
| `iac-modules-repo/network/tgw-peering` | Regional (network-hub) | `tgw-peering-v1.0.0` | Cross-region Transit Gateway peering (PLAN 5.2) as its own unit: one region requests the peering attachment, the other accepts it, so the two regional transit gateways do not depend on each other. No static routes over the peering yet |
| `iac-modules-repo/network/tgw-attachment` | Account (workload) | `tgw-attachment-v1.0.0` | Spoke-side transit gateway attachment: associates/propagates into exactly one route table (prod or nonprod, never both), optional central-egress default route |
| `iac-modules-repo/network/inspection-egress` | Regional (network-hub) | `inspection-egress-v1.0.0` | Central egress/inspection VPC (PLAN 5.3): NAT gateways one per AZ behind AWS Network Firewall with a stateful domain allow-list (`STRICT_ORDER`, drop by default); alert/flow logs to log-archive |
| `iac-modules-repo/network/central-endpoints` | Regional (shared-services) | `central-endpoints-v1.0.0` | Shared VPC interface endpoints (PLAN 5.4): one endpoint per service plus a private hosted zone per service, so spoke VPCs resolve the same endpoint centrally once their zone is associated |
| `iac-modules-repo/network/dns` | Regional (network-hub) | `dns-v1.0.0` | Route 53 Resolver inbound/outbound endpoints (PLAN 5.5), on-prem domain forwarding rules RAM-shared with the Workloads OU, resolver query logging, public hosted zones with delegated subdomains per workload account |
| `iac-modules-repo/compute/eks` | Regional | `eks-v1.0.0` | Hardened EKS, IMDSv2 (hop limit 1), private API endpoint, KMS rot., full audit logs |
| `iac-modules-repo/identity/human-access` | Account | `human-access-v2.0.0` | EKS access entries and the cluster view policy per team (the Identity Center permission sets moved to `identity-center`) |
| `iac-modules-repo/security/access-analyzer` | Account (security-tooling) | `access-analyzer-v1.0.0` | Organization-wide IAM Access Analyzer for external access and unused access, in the delegated-administrator account; findings flow to Security Hub |
| `iac-modules-repo/security/break-glass-alerts` | Account | `break-glass-alerts-v1.0.0` | EventBridge rules + encrypted SNS topic that email every BreakGlassAdmin sign-in (STS, console, and the Identity Center portal in management). Part of the just-in-time access design |
| `iac-modules-repo/security/log-archive` | Account (log-archive) | `log-archive-v1.0.0` | Object Lock (COMPLIANCE) S3 buckets for CloudTrail, Config, VPC flow logs, WAF, ALB and CloudFront logs, and S3 access logs, plus their KMS key. Bucket/trail names are a naming contract with `security/org-cloudtrail`, not shared state |
| `iac-modules-repo/security/org-cloudtrail` | Global (management) | `org-cloudtrail-v1.0.0` | The organization CloudTrail: one multi-region trail delivering to `security/log-archive`'s bucket, plus its own CloudWatch Logs group/SNS notifications (local KMS key). Optional S3 data events for confidential buckets and CloudTrail Lake |
| `iac-modules-repo/security/threat-detection` | Account (security-tooling), per region | `threat-detection-v1.0.0` | GuardDuty, Security Hub (FSBP + CIS v3, cross-region aggregation), Inspector v2 and Macie, auto-enabled organization-wide from the delegated-administrator account. Detective is opt-in |
| `iac-modules-repo/security/security-alerts` | Account | `security-alerts-v1.0.0` | EventBridge rules + encrypted SNS topic for GuardDuty/Security Hub findings (security-tooling) and root sign-in / Organizations policy changes (management). BreakGlassAdmin sign-in is `break-glass-alerts`, not duplicated here |
| `iac-modules-repo/security/auto-remediation` | Account (security-tooling) | `auto-remediation-v1.0.0` | Lambda that removes open SSH/RDP security group rules within seconds: a central EventBridge bus receives the forwarded event from the member account, the Lambda assumes `security-remediation` back into it. Config-rule trigger not built yet (needs PLAN 4.3) |
| `iac-modules-repo/identity/identity-center` | Global | `identity-center-v1.0.0` | IAM Identity Center for humans: the permission-set catalog (ReadOnly, Developer, PlatformEngineer, SecurityAudit, Billing, BreakGlassAdmin; 1h elevated / 8h others), ABAC session tags, groups (SCIM-synced or managed) and account assignments OU → group → permission set from the registry. No standing admin; elevated sets are just-in-time in Prod. Applied by the owner from the management account |
| `iac-modules-repo/identity/workload-identity` | Cluster | `workload-identity-v1.0.0` | EKS Pod Identity associations + IRSA federated OIDC fallback |
| `iac-modules-repo/governance/bootstrap-stacksets` | Global | `bootstrap-stacksets-v1.0.0` | Service-managed CloudFormation StackSets (one per GitHub Environment) that roll the Day-0 bootstrap template out to every member account in the targeted OUs. Applied by the owner from the management account |
| `iac-modules-repo/governance/organization` | Global | `organization-v1.0.0` | The AWS Organization (trusted service access, policy types), the OU tree (Security, Infrastructure, Workloads{Prod,NonProd}, Sandbox, Policy-Staging, Suspended) and baseline SCP guardrails attached to `guardrail_target_ous` (Policy-Staging by default). Applied by the owner from the management account |
| `iac-modules-repo/governance/data-perimeter` | Global | `data-perimeter-v1.0.0` | Resource Control Policies for S3, KMS, SQS and Secrets Manager (deny access from outside the organization, require TLS; sts is opt-in). Attached to Policy-Staging only by default. Applied by the owner from the management account |
| `iac-modules-repo/governance/budgets` | Account | `budgets-v1.0.0` | Monthly cost budget per account (alerts at 50/80/100 % actual, 100 % forecast) and a Cost Anomaly Detection monitor; amount and alert address come from the account registry |
| `iac-modules-repo/governance/cost-janitor` | Account (workload, dev) | `cost-janitor-v1.0.0` | Weekly Lambda that reports unattached EBS volumes, old snapshots, unassociated Elastic IPs and log groups without retention (PLAN 9.5). Report-only by default (`dry_run = true`); `keep=true` tag opt-out; dev only |
| `iac-modules-repo/governance/discovery-publisher` | Account | `discovery-publisher-v1.0.0` | Publishes the discovery contract (`/platform/<env>/<region>/...`) into the account from the outputs of the VPC, EKS and ACK stacks; the single owner of those parameter names |
| `iac-modules-repo/governance/account-baseline` | Account | `account-baseline-v1.0.0` | Applied to every account: `platform-workload-boundary`, account alias, password policy, S3 Block Public Access, EBS encryption and IMDSv2 defaults, VPC Block Public Access (PLAN 5.7, on by default), KMS CMKs per data class, the account discovery parameters, and (when given the auto-remediation Lambda's role ARN) the narrow `security-remediation` role it assumes. Not the state bucket or CI roles (those come from the Day-0 bootstrap) |
| `iac-modules-repo/governance/account-factory` | Global | `account-factory-v1.0.0` | Creates and places the member accounts from the account registry (`iac-live-repo/_config/accounts.hcl`, entries with `create = true`); accounts are never closed. Applied by the owner from the management account |
| `iac-modules-repo/identity/ack-cross-account` | Account | `ack-cross-account-v1.0.0` | ACK hub/spoke trust for one account: spoke role, scoped inline policy, `ack-tenant-boundary`, discovery parameter |

### 3. The Discovery Contract (SSM Parameter Store Service Catalog)
Per **PLAN.md Phase 18.1**, tenant Terraform modules never hardcode AWS IDs (VPC IDs, subnets, OIDC ARNs, cluster names). On every foundation stack apply, standard parameters are published to AWS SSM Parameter Store:

- `/platform/${env}/${region}/vpc/id`: The VPC ID
- `/platform/${env}/${region}/vpc/database_subnets`: Comma-delimited list of database subnet IDs
- `/platform/${env}/${region}/eks/cluster_name`: Name of the EKS cluster
- `/platform/${env}/${region}/eks/oidc_provider_arn`: EKS OIDC provider ARN for IRSA / Pod Identity
- `/platform/${env}/${region}/ack/cross_account_role_arn`: ACK controller cross-account role ARN for hub-spoke provisioning

The same names are written into **every workload account** (SSM is per account), by `governance/discovery-publisher` (vpc, eks, ack) and `governance/account-baseline` (`account/{id,ou}`, `kms/{general,confidential}_key_arn`, `iam/workload_boundary_arn`). Full contract: `docs/DISCOVERY_CONTRACT.md`.

Tenant Terraform ingests these parameters dynamically at plan time via `data "aws_ssm_parameter"`.

### 4. Release Automation & Monorepo Versioning
Independent per-module semantic versioning is automated using Google's **`release-please` manifest mode** (`release-please-config.json` + `.release-please-manifest.json` + `.github/workflows/release.yml`). Tags follow `<module>-vX.Y.Z` (e.g. `postgres-v1.0.0`, `eks-v1.0.0`, `vpc-v1.0.0`).

---

## 3. Essential Commands

All tooling is baked into the toolchain container (`.github/docker/Dockerfile`); locally install the equivalents (Terraform `1.15.1`, Terragrunt `1.0.3` pinned in Dockerfile ARGs and `.github/actions/setup-platform/action.yml`).

```bash
# Full local validation suite — compliance, fmt, terragrunt init+validate (dev), tflint.
# This is the pre-commit hook and the CI "smoke test"; run it before pushing.
./scripts/smoke-test.sh

# Formatting — MUST cover all three roots or CI fails (see static-analysis action)
terraform fmt -recursive iac-modules-repo iac-live-repo policy-library-repo
terragrunt hcl fmt

# Lint / security / policy
tflint --init && tflint --recursive --format=compact
make checkov        # same settings and result as the CI Checkov check (.checkov.yaml)
make verify-module MODULE=<category/name>   # ONE module, the CI tools, no AWS credentials (fmt, init, validate, tflint, checkov, test, conftest)
make image-scan     # build the toolbox image and Trivy-scan it (needs Docker)
conftest test --policy policy-library-repo/terraform <plan.json>   # policy runs against plan JSON, not HCL

# Plan/apply one account (uses run --all across the dependency graph)
make plan ACCOUNT=workloads-dev
cd iac-live-repo/workloads-dev && terragrunt run --all plan --non-interactive --log-format bare
cd iac-live-repo/workloads-dev && terragrunt run --all apply --non-interactive -auto-approve --log-format bare

# Plan/apply one stack only
cd iac-live-repo/workloads-dev/eu-central-1/eks && terragrunt plan --log-format bare

# Scaffold a new stack (one terragrunt.hcl) manually
./scripts/generate-module.sh <category/module-name> <account> <region>

# Install the pre-commit hook (fmt + checkov on every commit)
pre-commit install
```

---

## 4. How a stack is put together

A stack is **one `terragrunt.hcl`**. Nothing is merged from other files except `root.hcl`:

1. **The folder path is the config:** `iac-live-repo/<account>/<region or _global>/<stack>/terragrunt.hcl`. `<account>` must be a key in `iac-live-repo/_config/accounts.hcl` (the registry); `_global` means "account-wide, run from the primary region". Every folder name is checked by `scripts/check-account-registry.sh`.
2. **`iac-live-repo/root.hcl`** is the only file that looks anything up. It takes the account from the path and everything else from the registry in `_config/` (`accounts.hcl`, `regions.hcl`, `organization.hcl`), and **generates `provider.tf` and `backend.tf`** with `default_tags` (`Environment`, `Service`, `Project`, `ManagedBy`, `Account`, `Owner`, `DataClassification`). The state bucket is `tg-state-<account-id>-<region>`, the state key is the path (`path_relative_to_include()`). Do not add provider/backend blocks by hand.
3. **The stack file** includes `root.hcl` (`expose = true`), sets `terraform.source` to the local module (`${get_repo_root()}/iac-modules-repo/<category>/<module>`), declares its `dependency` blocks (with `mock_outputs` for plan-time) and every input. Short template:

   ```hcl
   include "root" {
     path   = find_in_parent_folders("root.hcl")
     expose = true
   }
   terraform {
     source = "${get_repo_root()}/iac-modules-repo/compute/eks"
   }
   dependency "vpc" {
     config_path  = "../vpc"
     mock_outputs = { vpc_id = "vpc-12345678" }
   }
   inputs = {
     cluster_name = "main-eks-dev"
     vpc_id       = dependency.vpc.outputs.vpc_id
   }
   ```
4. **Where values come from:** account and region values are `include.root.locals.<name>` (`account_name`, `account_id`, `env`, `ou`, `alias`, `owner`, `data_classification`, `aws_region`, plus `registry`, `regions`, `organization`). Everything else (cluster names, sizes, CIDRs) is a literal in the stack file.
5. **The one-file rule:** a stack never calls `read_terragrunt_config`, `get_env(` or `find_in_parent_folders` (except for `root.hcl`). `scripts/check-account-registry.sh` fails CI otherwise.

The folder layout is load-bearing: the path drives the account, the region, the state key and the `Service` tag. `env` comes from the registry (`dev`/`staging`/`prod`/`global`), not from the folder name, and regions must be allowed for the account's OU in `_config/regions.hcl`. There is no `assume_role`: CI uses OIDC directly into the target account.

The catalog golden-path templates (`iac-agents-repo/catalog/templates/`) intentionally use pinned `tfr://` registry modules (third-party, versioned), while platform stacks use local `iac-modules-repo` sources.

---

## 5. Governance Gates (What Will Block a PR)

These are enforced against the **Terraform plan JSON** in CI (`reusable-terragrunt.yml`), so a change can pass `terraform validate` and still fail here:

- **OPA/Conftest** (`policy-library-repo/terraform/*.rego`, package `main`):
  - `require_tags.rego` — every created/updated resource must carry `Service`, `Environment`, `Project`, `Owner` and `DataClassification` tags (checked in `tags_all`). The `root.hcl` `default_tags` normally satisfies this (`Owner` / `DataClassification` come from the registry via `root.hcl`); resources that escape provider default tags will fail.
  - `no_legacy_instances.rego` — blocks old instance families (`t2.`, `m3.`, `m4.`, `c3.`, `c4.`).
  - `deny_admin_attachments.rego`, `deny_public_s3.rego`, `deny_open_ingress.rego`, `deny_iam_wildcards.rego`, `require_encryption.rego` — see `docs/CICD.md` for what each blocks. Shared helpers live in `helpers.rego` (all files are package `main`, so helper names must not collide).
- **Checkov** — the only Checkov settings file is `.checkov.yaml`; always run it through `./scripts/run-checkov.sh` (or `make checkov`), which is what CI and the pre-commit hook run, so the result matches. It blocks (no `soft_fail`). Accept a finding with an inline `#checkov:skip=<ID>: <reason>` on that resource; the repo-wide `skip-check` list is only for checks that do not apply to the platform. Plan-stage Checkov runs on every `tfplan.json`. Checkov IAM checks read only Allow statements, so a Deny does not clear a finding. The Checkov version is pinned in `.github/docker/Dockerfile` (`CHECKOV_VERSION`, Renovate-managed).
- **Trivy** — scans the toolbox image only (it no longer scans Terraform, PLAN 8.9). `publish-toolchain.yml` scans the toolbox image (`trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`) before pushing it; `make image-scan` runs it locally.
- Gate ownership (8.9): tflint = written correctly, Checkov = secure, conftest/Rego = this org's rules, Trivy = the toolbox image.
- **Infracost** — posts a per-module cost breakdown PR comment, and fails a PR whose monthly cost rises ≥ $100, or ≥ $10 and ≥ 20 %, unless it has the `cost-approved` label.

---

## 6. CI/CD Pipeline

- `terragrunt.yml` — main orchestrator. Static analysis + one reusable stack per account run in parallel (the account matrix is generated from `iac-live-repo/_config/accounts.hcl` by `scripts/generate_account_matrix.py`; an account runs only with `ci = true`, a live folder and a real account id). On push to `main`, an `apply` matrix job runs one account at a time (management, core, dev, staging, prod), each in the account's GitHub Environment (prod requires manual approval).
- `reusable-terragrunt.yml` — per-account plan → governance (OPA on every plan, Checkov on every plan) → cost analysis. The cost gate in that last job marks the PR's cost-analysis check red on a big monthly rise; it blocks merging only once that check is required in branch protection (main is not protected yet). Plans are generated as `tfplan.bin`, converted to `tfplan.json`, uploaded as artifacts, and consumed by the gate jobs.
- Auth is **zero-key OIDC** with two roles per account, straight into the target account (no shared role, no role chaining, no per-environment role variables): plan/governance/drift jobs assume the read-only `arn:aws:iam::<account-id>:role/github-actions-plan` (trusted from PRs and `main`); apply/destroy jobs assume `.../github-actions-apply` (trusted only from that account's GitHub Environment: `management`, `core`, `dev`, `prod`), via `setup-platform`. The account id comes from the registry. No static AWS credentials exist.
- `drift-detection.yml` — nightly matrix over the account matrix; manages one GitHub Issue per account (create/comment/auto-close) and prompts for ChatOps reconciliation.
- `chatops_generator.yml` — listens for `/generate` and `/reconcile` issue/PR comments to trigger automated module authoring and PR creation.
- `pipeline_healer.yml` — triggers on a failed "Terragrunt CI/CD" run and executes `iac-agents-repo/ci_healer/healer_runner.py`.

---

## 7. Conventions & Gotchas

- **Account IDs come from the registry** (`iac-live-repo/_config/accounts.hcl`, read by `root.hcl` from the account folder name), never `get_aws_account_id()` in `root.hcl`: that returns the caller's account, so `allowed_account_ids` would compare the caller with itself and never fail. The registry also carries `owner` and `data_classification` (used for default tags).
- **A value lives in exactly one place:** the stack file, or the registry via `root.hcl`. Setting the same value in two files is how dev EKS got `min_size` twice in PR #71.
- **EKS API endpoint is private by default.** `api_allowed_cidrs` in the EKS stack (empty by default) turns on the public endpoint and restricts it to those CIDRs; the module rejects public access with no CIDRs.
- **Never hand-write `provider.tf` or `backend.tf`** — they are generated by `root.hcl`. Editing them has no effect (`if_exists = "overwrite_terragrunt"`).
- When adding a module, create the stack `terragrunt.hcl` in each account folder that needs it (`scripts/generate-module.sh`); don't inline module logic into a live dir.
- `fmt` must pass across `iac-modules-repo`, `iac-live-repo` **and** `policy-library-repo` — a stray unformatted `.tf`/`.hcl` in any of the three fails Gate 1. The CloudFormation template in `iac-live-repo/_bootstrap/cloudformation/` is checked by `cfn-lint` instead.
- Rego policies target Rego v1 (`import rego.v1`) and package `main`.
- Cost / resilience knobs (spot/scaling, `enable_nat_gateway`, `single_nat_gateway`) are literals in the dev stacks; keep dev cheap (spot, min sizes) — the README's FinOps numbers depend on it.

### Local agent guardrails (PLAN 11.2)

These rules apply to **any** coding agent working in this repo, whatever the tool. They are written here once; `.claude/settings.json` +
`.claude/hooks/guard.py` are one implementation (Claude Code). Another tool can call the same script or implement the same rules.

1. **After every edit inside a module**, run `make verify-module MODULE=<category/name>` and read the short result
   (`<tool> <check-id> <file>:<line>`, one line per failure). Fix the code, not the check.
2. **Never run** `terraform` / `terragrunt` `apply`, `destroy`, `import`, `force-unlock`, `state rm|mv|push`, or `run --all` without a
   read-only command (`plan`, `validate`, ...). This includes `cd x && ...` chains, `bash -c`, `sudo`, `xargs` and `make` targets named
   like `apply`. `plan`, `validate`, `fmt`, `init`, `test` and `render` are fine.
3. **Never edit** `.checkov.yaml`, `.trivyignore`, `policy-library-repo/`, `.claude/settings.json` or `.claude/hooks/`. They decide what
   "passing" means, so only a human changes them. If a check is wrong, say so in the PR and let the owner decide.
4. **Attempt limit:** after **3** failed `verify-module` runs in a row on the same module, stop editing it and hand over to a human with
   the last result. A human clears it with `python3 .claude/hooks/guard.py reset <category/name>`. Set `AGENT_MAX_VERIFY_ATTEMPTS` to change N.
5. Never push to `main`, never bypass the prod approval gate, never invent account IDs (see `PLAN.md`).
6. Check a live stack's final inputs with `terragrunt render --format json` (works offline, see command), never by guessing from one file. Command: `cd <leaf> && env -u AWS_PROFILE AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null terragrunt render --format json --non-interactive --log-format bare 2>/dev/null | jq '.inputs'`.

**The hooks are not the control.** They run on a laptop and can be switched off; they exist to save time and stop honest mistakes.
The real controls are: CODEOWNERS on the paths in rule 3, branch protection on `main`, and that no agent has credentials that can apply
(no agent may assume `github-actions-apply`). See `docs/AGENT_AUTONOMY.md` for what is enforced where, and for the known gaps.
Tests: `python3 -m unittest discover -s .claude/hooks` (`test_guard.py`).

---

## 8. Agent Registry & Platform Capabilities

The agent registry, autonomy tiers, catalog specs, and CLI instructions are documented in:

👉 **[`iac-agents-repo/README.md`](iac-agents-repo/README.md)**

See also:
- **Architecture & Workflows**: [`iac-agents-repo/docs/IAC_PLATFORM_AGENT.md`](iac-agents-repo/docs/IAC_PLATFORM_AGENT.md)
- **Autonomy Controls & Governance**: [`iac-agents-repo/docs/AGENT_AUTONOMY.md`](iac-agents-repo/docs/AGENT_AUTONOMY.md)
- **Interactive Visualizers**: [`docs/diagrams/ai_agentic_workflows.html`](docs/diagrams/ai_agentic_workflows.html) and [`docs/diagrams/feedback_loops_quality_flywheel.html`](docs/diagrams/feedback_loops_quality_flywheel.html)

---

## 9. Communication & Diagram Standards

- **STRICT PROHIBITION: NO Mermaid Diagrams**: Never generate Mermaid flowcharts, sequence diagrams, or graph syntax in chat outputs or documentation. They fail to render reliably across different IDEs and markdown viewers.
- **Accepted Formats**:
  1. **Clean Plain Text / ASCII Box Formats**: Simple, readable text layouts and structured tables.
  2. **Rendered Diagram Images**: For complex architectural flows, use the image generation tool to produce high-resolution, professional visual architecture diagrams saved as media artifacts.
