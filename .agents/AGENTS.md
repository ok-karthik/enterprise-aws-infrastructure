# Enterprise IaC Platform & SRE Agent Registry

This document serves as the comprehensive single source of truth for AI agents (Claude Code, Antigravity, custom scripts) and engineers building, auditing, and maintaining the **Enterprise AWS Platform (Terragrunt)**.

---

## 1. What This Repository Is

A multi-environment AWS Infrastructure-as-Code platform built with **Terragrunt + Terraform**. There is no application code — the "product" is HCL config, reusable Terraform modules, OPA/Rego policies, and the GitHub Actions pipeline that plans/applies them. An autonomous Python "healer" agent auto-remediates failed CI runs, and an on-demand IaC Platform Agent scaffolds and reconciles compliant modules.

### Infrastructure Layout
A directory ending in `-repo` is a separate Git repository in a real company (see `docs/adr/0001-repository-topology.md`); here they live side by side so the whole foundation can be read from one checkout.

*   `/iac-modules-repo/`: Custom reusable Terraform modules, versioned per module (`<module>-vX.Y.Z`). Pure `.tf`, no environment specifics, no provider blocks.
*   `/foundation-live-repo/`: The landing zone: `_global/` (organization, bootstrap StackSets; management account), `_envcommon/governance/` blueprints, its own `root.hcl`, and `_bootstrap/`. Security + cloud-infra approve changes.
*   `/workloads-live-repo/`: Platform stacks in workload accounts: `dev/`, `prod/`, `_envcommon/{compute,data,network}/`, its own `root.hcl`, and `scripts/` (smoke test, module generator). The platform team approves changes.
*   `/foundation-live-repo/_bootstrap/` (inside the foundation repo): Day-0 **CloudFormation** stack `platform-bootstrap` (`cloudformation/account-bootstrap.yaml`: S3 state bucket, GitHub OIDC provider, `github-actions-plan` / `github-actions-apply` roles + permissions boundary) and the `bootstrap.sh` that deploys it. Run once by a human in the management account; member accounts get it through StackSets (PLAN 2.0b). Terragrunt never creates the state bucket: **no command may pass `--backend-bootstrap`**.
*   `/policy-library-repo/terraform/`: Rego-based OPA compliance rules enforced against Terraform plan JSON.
*   `/.agents/`: Catalog, prompts, eval fixtures, SRE policies, and scripts for autonomous agents.

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
Applied and maintained directly by this platform via Terragrunt environments (`workloads-live-repo/{dev,prod}/...` and `foundation-live-repo/management/_global/`):

| Module Path | Scope | Release Tag | Purpose |
|---|---|---|---|
| `iac-modules-repo/network/vpc` | Regional | `vpc-v1.0.0` | Multi-AZ VPC, flow logs, deny-all default NACL, private & database subnets |
| `iac-modules-repo/compute/eks` | Regional | `eks-v1.0.0` | Hardened EKS, IMDSv2 (hop limit 1), private API endpoint, KMS rot., full audit logs |
| `iac-modules-repo/identity/human-access` | Account | `human-access-v2.0.0` | EKS access entries and the cluster view policy per team (the Identity Center permission sets moved to `identity-center`) |
| `iac-modules-repo/security/access-analyzer` | Account (security-tooling) | `access-analyzer-v1.0.0` | Organization-wide IAM Access Analyzer for external access and unused access, in the delegated-administrator account; findings flow to Security Hub |
| `iac-modules-repo/security/break-glass-alerts` | Account | `break-glass-alerts-v1.0.0` | EventBridge rules + encrypted SNS topic that email every BreakGlassAdmin sign-in (STS, console, and the Identity Center portal in management). Part of the just-in-time access design |
| `iac-modules-repo/identity/identity-center` | Global | `identity-center-v1.0.0` | IAM Identity Center for humans: the permission-set catalog (ReadOnly, Developer, PlatformEngineer, SecurityAudit, Billing, BreakGlassAdmin; 1h elevated / 8h others), ABAC session tags, groups (SCIM-synced or managed) and account assignments OU → group → permission set from the registry. No standing admin; elevated sets are just-in-time in Prod. Applied by the owner from the management account |
| `iac-modules-repo/identity/workload-identity` | Cluster | `workload-identity-v1.0.0` | EKS Pod Identity associations + IRSA federated OIDC fallback |
| `iac-modules-repo/governance/bootstrap-stacksets` | Global | `bootstrap-stacksets-v1.0.0` | Service-managed CloudFormation StackSets (one per GitHub Environment) that roll the Day-0 bootstrap template out to every member account in the targeted OUs. Applied by the owner from the management account |
| `iac-modules-repo/governance/organization` | Global | `organization-v1.0.0` | The AWS Organization (trusted service access, policy types), the OU tree (Security, Infrastructure, Workloads{Prod,NonProd}, Sandbox, Policy-Staging, Suspended) and baseline SCP guardrails attached to `guardrail_target_ous` (Policy-Staging by default). Applied by the owner from the management account |
| `iac-modules-repo/governance/budgets` | Account | `budgets-v1.0.0` | Monthly cost budget per account (alerts at 50/80/100 % actual, 100 % forecast) and a Cost Anomaly Detection monitor; amount and alert address come from the account registry |
| `iac-modules-repo/governance/discovery-publisher` | Account | `discovery-publisher-v1.0.0` | Publishes the discovery contract (`/platform/<env>/<region>/...`) into the account from the outputs of the VPC, EKS and ACK stacks; the single owner of those parameter names |
| `iac-modules-repo/governance/account-baseline` | Account | `account-baseline-v1.0.0` | Applied to every account: `platform-workload-boundary`, account alias, password policy, S3 Block Public Access, EBS encryption and IMDSv2 defaults, KMS CMKs per data class, and the account discovery parameters. Not the state bucket or CI roles (those come from the Day-0 bootstrap) |
| `iac-modules-repo/governance/account-factory` | Global | `account-factory-v1.0.0` | Creates and places the member accounts from the account registry (`foundation-live-repo/_config/accounts.hcl`, entries with `create = true`); accounts are never closed. Applied by the owner from the management account |
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
./workloads-live-repo/scripts/smoke-test.sh

# Formatting — MUST cover all four roots or CI fails (see static-analysis action)
terraform fmt -recursive iac-modules-repo foundation-live-repo workloads-live-repo policy-library-repo
terragrunt hcl fmt

# Lint / security / policy
tflint --init && tflint --recursive --format=compact
trivy config . --severity CRITICAL,HIGH --ignorefile .trivyignore --tf-exclude-downloaded-modules
make checkov        # same settings and result as the CI Checkov check (.checkov.yaml)
make image-scan     # build the toolbox image and Trivy-scan it (needs Docker)
conftest test --policy policy-library-repo/terraform <plan.json>   # policy runs against plan JSON, not HCL

# Plan/apply a single environment stack (uses run --all across the dependency graph)
cd workloads-live-repo/workloads-dev && terragrunt run --all plan --non-interactive
cd workloads-live-repo/workloads-dev && terragrunt run --all apply --non-interactive -auto-approve

# Plan/apply one module only
cd workloads-live-repo/workloads-dev/eu-central-1/compute/eks && terragrunt plan

# Scaffold a new module manually
./workloads-live-repo/scripts/generate-module.sh <category/module-name> [env] [region]

# Install the pre-commit hook (fmt + trivy + checkov on every commit)
pre-commit install
```

---

## 4. Architecture: The Terragrunt Inheritance Chain

The core pattern is **strict separation of "blueprint" from "live config"**, kept 100% DRY through a layered `include`/`read_terragrunt_config` chain:

1. **`iac-modules-repo/`** — generic, reusable Terraform (`network/vpc`, `compute/eks`). Pure `.tf`, no environment specifics. Security hardening lives *here* (VPC deny-all NACLs, EKS KMS encryption), not just in CI.

2. **`root.hcl`** (one copy in each live repo, kept identical) — the root included by every leaf. It **generates `provider.tf` and `backend.tf`** at runtime (`generate` blocks) and injects `default_tags` (`Environment`, `Service`, `Project`, `ManagedBy`, `Account`). The S3 backend bucket name and `default_tags` are computed here — do not add provider/backend blocks by hand in modules.

3. **`workloads-live-repo/_envcommon/<category>/<module>.hcl`** — the shared blueprint per module type. Sets `terraform.source` (pointing into `iac-modules-repo/` or registry `tfr://`), declares `dependency` blocks (with `mock_outputs` for plan-time), and default `inputs`. Cross-module wiring (EKS → VPC subnets) lives here.

4. **Data files loaded via `find_in_parent_folders`:**
   - `<account>/account.hcl` — `aws_account_id`, `account_name` (= folder name), `ou`, `env` (`dev|staging|prod|global`), `owner`, `data_classification`; must match the account's entry in `foundation-live-repo/_config/accounts.hcl`
   - `<account>/env.hcl` — `env` (same as account.hcl), `cluster_name`, cost-scaling knobs (`min_size`, `desired_size`, `enable_nat_gateway`) and `module_versions` (the release tag of each `iac-modules-repo` module this environment uses; `_envcommon` builds `terraform.source` from it, or from the checkout when `IAC_MODULES_LOCAL` is set — see `docs/CICD.md`)
   - `<account>/<region|_global>/region.hcl` — `aws_region` (must be in `_config/regions.hcl`)

5. **`workloads-live-repo/<account>/<region>/<category>/<module>/terragrunt.hcl`** (`<account>` = `workloads-dev`, `workloads-prod`, ...; the management account is `foundation-live-repo/management/_global/...`) — the leaf. Includes `root` + the matching `_envcommon` file (`expose = true`) and only overrides env-specific values (e.g. dev EKS shrinks `min_size`/`max_size`/`desired_size`).

`path_relative_to_include()` drives naming everywhere (state key, `Service` tag, env detection), so **directory layout is load-bearing** — the `<account>/<region|_global>/<category>/<module>` shape is a contract, not a convention. `env` comes from `account.hcl` (`dev`/`staging`/`prod`/`global`), not from the folder name, and regions must be in `_config/regions.hcl` (enforced by `smoke-test.sh`). There is no `assume_role`: CI uses OIDC directly into the target account.

---

## 5. Governance Gates (What Will Block a PR)

These are enforced against the **Terraform plan JSON** in CI (`reusable-terragrunt.yml`), so a change can pass `terraform validate` and still fail here:

- **OPA/Conftest** (`policy-library-repo/terraform/*.rego`, package `main`):
  - `require_tags.rego` — every created/updated resource must carry `Service`, `Environment`, `Project`, `Owner` and `DataClassification` tags (checked in `tags_all`). The `root.hcl` `default_tags` normally satisfies this (`Owner` / `DataClassification` come from `account.hcl`); resources that escape provider default tags will fail.
  - `no_legacy_instances.rego` — blocks old instance families (`t2.`, `m3.`, `m4.`, `c3.`, `c4.`).
  - `deny_admin_attachments.rego`, `deny_public_s3.rego`, `deny_open_ingress.rego`, `deny_iam_wildcards.rego`, `require_encryption.rego` — see `docs/CICD.md` for what each blocks. Shared helpers live in `helpers.rego` (all files are package `main`, so helper names must not collide).
- **Checkov** — the only Checkov settings file is `.checkov.yaml`; always run it through `./workloads-live-repo/scripts/run-checkov.sh` (or `make checkov`), which is what CI and the pre-commit hook run, so the result matches. It blocks (no `soft_fail`). Accept a finding with an inline `#checkov:skip=<ID>: <reason>` on that resource; the repo-wide `skip-check` list is only for checks that do not apply to the platform. Plan-stage Checkov runs on every `tfplan.json`. Checkov IAM checks read only Allow statements, so a Deny does not clear a finding. The Checkov version is pinned in `.github/docker/Dockerfile` (`CHECKOV_VERSION`, Renovate-managed).
- **Trivy** — `trivy config` (Terraform, `CRITICAL,HIGH`, suppressions in `.trivyignore`) stays until PLAN 8.9 step 5. `publish-toolchain.yml` also scans the toolbox image (`trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`) before pushing it; `make image-scan` runs it locally.
- Gate ownership (8.9): tflint = written correctly, Checkov = secure, conftest/Rego = this org's rules, Trivy = the toolbox image.
- **Infracost** — posts a per-module cost breakdown PR comment (and blocks agent changes exceeding configured budget thresholds).

---

## 6. CI/CD Pipeline

- `terragrunt.yml` — main orchestrator. Static analysis + one reusable stack per account run in parallel (the account matrix is generated from `foundation-live-repo/_config/accounts.hcl` by `workloads-live-repo/scripts/generate_account_matrix.py`; an account runs only with `ci = true`, a live folder and a real account id). On push to `main`, an `apply` matrix job runs one account at a time (management, core, dev, staging, prod), each in the account's GitHub Environment (prod requires manual approval).
- `reusable-terragrunt.yml` — per-account plan → governance (OPA on every plan, Checkov on every plan, Trivy) → cost analysis. Plans are generated as `tfplan.bin`, converted to `tfplan.json`, uploaded as artifacts, and consumed by the gate jobs.
- Auth is **zero-key OIDC** with two roles per account, straight into the target account (no shared role, no role chaining, no per-environment role variables): plan/governance/drift jobs assume the read-only `arn:aws:iam::<account-id>:role/github-actions-plan` (trusted from PRs and `main`); apply/destroy jobs assume `.../github-actions-apply` (trusted only from that account's GitHub Environment: `management`, `core`, `dev`, `prod`), via `setup-platform`. The account id comes from the registry. No static AWS credentials exist.
- `drift-detection.yml` — nightly matrix over the account matrix; manages one GitHub Issue per account (create/comment/auto-close) and prompts for ChatOps reconciliation.
- `chatops_generator.yml` — listens for `/generate` and `/reconcile` issue/PR comments to trigger automated module authoring and PR creation.
- `pipeline_healer.yml` — triggers on a failed "Terragrunt CI/CD" run and executes `.agents/scripts/healer_runner.py`.

---

## 7. Conventions & Gotchas

- **Account IDs come from `account.hcl`**, never `get_aws_account_id()` in `root.hcl`: that returns the caller's account, so `allowed_account_ids` would compare the caller with itself and never fail. Every `account.hcl` also carries `owner` and `data_classification` (used for default tags).
- **EKS API endpoint is private by default.** `env.hcl` `api_allowed_cidrs` (empty by default) turns on the public endpoint and restricts it to those CIDRs; the module rejects public access with no CIDRs.
- **Never hand-write `provider.tf` or `backend.tf`** — they are generated by `root.hcl`. Editing them has no effect (`if_exists = "overwrite_terragrunt"`).
- When adding a module, create both the blueprint (`_envcommon/.../<m>.hcl` → `terraform.source`) and the leaf `terragrunt.hcl` in each env; don't inline module logic into a live dir.
- `fmt` must pass across `iac-modules-repo`, `foundation-live-repo`, `workloads-live-repo` **and** `policies` — a stray unformatted `.tf`/`.hcl` in any of the four fails Gate 1. The CloudFormation template in `foundation-live-repo/_bootstrap/cloudformation/` is checked by `cfn-lint` instead.
- Rego policies target Rego v1 (`import rego.v1`) and package `main`.
- Cost / resilience knobs (spot/scaling, `enable_nat_gateway`, `single_nat_gateway`) live in `env.hcl`; keep dev cheap (spot, min sizes) — the README's FinOps numbers depend on it.

---

## 8. Agent Registry & Platform Capabilities

### 1. IaC Architect (`.agents/prompts/architect.md`)
*   **Role**: Senior Cloud Infrastructure Architect.
*   **Responsibility**: Writes valid Terraform/Terragrunt HCL.
*   **Directives**: Must use dry-run testing (`-backend=false` init / `terraform validate`) and strictly respect variable declarations under `/workloads-live-repo`.

### 2. Policy Auditor (`.agents/prompts/auditor.md`)
*   **Role**: Security & Governance Compliance Officer.
*   **Responsibility**: Performs independent semantic review and automated compliance checks, returning `STATUS: PASSED/FAILED`.
*   **Directives**: Enforces Rego policy checks in `/policy-library-repo/terraform/`, Checkov/TFLint standards, and semantic sanity checks (no wildcard IAM, no public ingress on DB/SSH ports).

### 3. Pipeline Healer (`.agents/prompts/ci_healer.md`, `.agents/scripts/healer_runner.py`)
*   **Role**: Incident & CI/CD Recovery Specialist.
*   **Responsibility**: Runs automatically on workflow failure (`pipeline_healer.yml`), isolates root cause from GitHub runner logs, auto-resolves provider lock mismatches, or generates a minimal LLM git patch and pushes to the PR branch.
*   **Directives**: Prioritize minimal diffs. Safe directory config and ephemeral container root execution.

### 4. IaC Generation & Platform Agent (`.agents/prompts/iac_agent.md`, `.agents/scripts/iac_agent.py`)
*   **Role**: Autonomous Platform Engineering & SRE Agent — provides self-service infrastructure generation, drift reconciliation, and change-risk governance.
*   **Capabilities**:
    1.  **Golden-Path Catalog** (`.agents/catalog/golden-paths.yaml`): Deterministic keyword matching renders pre-vetted modules (`data-s3-encrypted`, `data-rds-postgres`) with zero LLM-authored HCL.
    2.  **Uncatalogued Requests**: LLM classification (`classify_request`) + deterministic scaffolding (`scaffold_skeleton`) + diff-only generation (`generate_diff`) informed by live Rego/Checkov policy digests (`build_policy_digest`).
    3.  **Semantic Second-Opinion Gate**: Every diff passes independent LLM review via the Policy Auditor persona before validation.
    4.  **Full Validation Ladder**: Offline validation (`-backend=false`), `tflint`, OPA/Conftest, Checkov, Trivy, and Infracost cost threshold gating.
    5.  **Drift-to-Diff Reconciliation** (`--reconcile`): Ingests Terraform plan drift outputs and generates corrective HCL diffs.
    6.  **ChatOps Trigger** (`.github/workflows/chatops_generator.yml`): Responds to `/generate` and `/reconcile` issue comments.
    7.  **Multi-Module Graph Decomposition** (`--graph`): Topologically decomposes multi-service requests (VPC + EKS + RDS) with cross-module dependency injection.
    8.  **Model Context Protocol (MCP) Client** (`.agents/scripts/mcp_client.py`): Direct JSON-RPC doc querying with GitHub raw fallback.
    9.  **Developer Portal / Backstage Integration** (`.agents/backstage/`): Software templates (`s3-bucket.yaml`, `rds-postgres.yaml`), catalog registration, and CLI runner.
    10. **SRE Error-Budget Guardrails** (`.agents/sre/error_budgets.yaml`): Blocks unapproved production proposals when the error budget is below 10%.
    11. **Telemetry & Health Metrics** (`.agents/metrics/runs.jsonl`, `.agents/scripts/iac_agent_metrics.py`): Append-only metrics tracking success rates, ladder failure causes, and high-demand module types.
*   **Usage**:
    ```bash
    # Generate single module (offline dry-run)
    python3 .agents/scripts/iac_agent.py --request "add an S3 bucket for artifacts" --dry-run

    # Multi-module graph decomposition
    python3 .agents/scripts/iac_agent.py --request "stand up VPC and RDS" --graph --dry-run

    # Local Platform HTTP API server
    python3 .agents/scripts/iac_agent.py --serve --port 8000

    # Display health metrics summary
    python3 .agents/scripts/iac_agent.py --metrics-summary

    # Run eval and test suite
    python3 .agents/scripts/iac_agent_eval.py
    python3 -m unittest discover -s .agents/tests
    ```
*   **Documentation & Visual Flow**: See **[docs/IAC_PLATFORM_AGENT.md](../docs/IAC_PLATFORM_AGENT.md)** for complete end-to-end architecture flow diagrams, ChatOps triggers, Backstage IDP runner, and setup instructions.

---

## 9. Communication & Diagram Standards

- **STRICT PROHIBITION: NO Mermaid Diagrams**: Never generate Mermaid flowcharts, sequence diagrams, or graph syntax in chat outputs or documentation. They fail to render reliably across different IDEs and markdown viewers.
- **Accepted Formats**:
  1. **Clean Plain Text / ASCII Box Formats**: Simple, readable text layouts and structured tables.
  2. **Rendered Diagram Images**: For complex architectural flows, use the image generation tool to produce high-resolution, professional visual architecture diagrams saved as media artifacts.
