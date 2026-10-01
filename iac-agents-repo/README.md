# Autonomous IaC Platform Agents & Healer (`iac-agents-repo`)

Autonomous engineering tooling for the Enterprise AWS Platform: an on-demand **IaC Platform Agent** for scaffolding, drift reconciliation, and change-risk governance, and an autonomous **Pipeline Healer** for CI failure remediation.

## Architecture & Visual Flows

Interactive and static visual diagrams are maintained in `docs/diagrams/` and published to GitHub Pages:
- **[🤖 AI Agentic Workflows Architecture](https://ok-karthik.github.io/enterprise-aws-infrastructure/diagrams/ai_agentic_workflows.html)** ([local source](../docs/diagrams/ai_agentic_workflows.html)): Scaffolding, drift reconciliation, second-opinion gates, and MCP integration.
- **[🔄 3-Tier Feedback Loops & Quality Flywheel](https://ok-karthik.github.io/enterprise-aws-infrastructure/diagrams/feedback_loops_quality_flywheel.html)** ([local source](../docs/diagrams/feedback_loops_quality_flywheel.html)): Fast local feedback, PR policy enforcement, and live health telemetry.

---

## Agent Registry & Platform Capabilities

### 1. IaC Architect (`prompts/architect.md`)
* **Role**: Senior Cloud Infrastructure Architect.
* **Responsibility**: Writes valid, hardened Terraform and Terragrunt HCL.
* **Directives**: Dry-run testing (`-backend=false` init / `terraform validate`), strict adherence to variable definitions under `workloads-live-repo` and `iac-modules-repo`.

### 2. Policy Auditor (`prompts/auditor.md`)
* **Role**: Security & Governance Compliance Officer.
* **Responsibility**: Performs independent semantic review and automated compliance checks, returning `STATUS: PASSED/FAILED`.
* **Directives**: Enforces Rego policy checks in `policy-library-repo/terraform/`, Checkov/TFLint standards, and semantic guardrails (no wildcard IAM, no public DB/SSH ports).

### 3. Pipeline Healer (`prompts/ci_healer.md`, `ci_healer/healer_runner.py`)
* **Role**: Incident & CI/CD Recovery Specialist.
* **Responsibility**: Triggers automatically on workflow failure (`.github/workflows/pipeline_healer.yml`), isolates root causes from GitHub Actions logs, fixes provider lock mismatches, or synthesizes minimal LLM git patches pushed to the PR branch.
* **Directives**: Enforces strict safety limits via `ci_healer/healer_guards.py`: **never pushes to `main`**, only runs against open PRs, capped at a 3-commit retry ceiling, and cannot alter protected security/policy files.

### 4. IaC Generation & Platform Agent (`prompts/iac_agent.md`, `iac_agent/iac_agent.py`)
* **Role**: Autonomous Platform Engineering & SRE Agent providing self-service infrastructure generation, drift reconciliation, and change-risk governance.
* **Capabilities**:
  1. **Golden-Path Catalog** (`catalog/golden-paths.yaml`): Deterministic keyword matching renders pre-vetted modules (`data-s3-encrypted`, `data-rds-postgres`) with zero LLM-authored HCL.
  2. **Uncatalogued Requests**: LLM classification (`classify_request`) + deterministic scaffolding (`scaffold_skeleton`) + diff-only generation (`generate_diff`) informed by live Rego/Checkov policy digests (`build_policy_digest`).
  3. **Semantic Second-Opinion Gate**: Every diff passes independent LLM review via the Policy Auditor persona before validation.
  4. **Full Validation Ladder**: Offline validation (`-backend=false`), `tflint`, OPA/Conftest, Checkov, and Infracost cost threshold gating.
  5. **Drift-to-Diff Reconciliation** (`--reconcile`): Ingests Terraform plan drift outputs and generates corrective HCL diffs.
  6. **ChatOps Trigger** (`.github/workflows/chatops_generator.yml`): Responds to `/generate` and `/reconcile` issue comments.
  7. **Multi-Module Graph Decomposition** (`--graph`): Topologically decomposes multi-service requests (VPC + EKS + RDS) with cross-module dependency injection.
  8. **Model Context Protocol (MCP) Client** (`iac_agent/mcp_client.py`): Direct JSON-RPC doc querying with GitHub raw fallback.
  9. **Developer Portal / Backstage Integration** (`integrations/backstage/`): Software templates (`s3-bucket.yaml`, `rds-postgres.yaml`), catalog registration, and CLI runner.
  10. **SRE Error-Budget Guardrails** (`sre/error_budgets.yaml`): Blocks unapproved production proposals when the error budget is below 10%.
  11. **Telemetry & Health Metrics** (`metrics/runs.jsonl`, `iac_agent/iac_agent_metrics.py`): Append-only metrics tracking success rates, ladder failure causes, and high-demand module types.

---

## Autonomy Levels & Human-in-the-Loop Controls

For full autonomy governance, consult **[docs/AGENT_AUTONOMY.md](docs/AGENT_AUTONOMY.md)** and **[docs/AGENTIC_ADOPTION.md](docs/AGENTIC_ADOPTION.md)**:

| Tier | Role | Actions Allowed | Human Oversight |
|---|---|---|---|
| **Tier 1: Read-Only** | Exploration & Audit | `plan`, `validate`, read docs, query MCP | Autonomous |
| **Tier 2: Scaffolding** | IaC Generation | Generate branch, write code, run verification | PR review & approval required |
| **Tier 3: CI Healing** | Pipeline Healer | Max 3 commits on existing PR branch | Auto-runs on failure; PR merge requires human |
| **Tier 4: Production Apply** | Infrastructure Apply | None (Agents never execute `apply` or `destroy`) | **Strictly human step** via GitHub Environment approvals |

---

## How to Run Locally

```bash
# Setup virtual environment and dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r iac-agents-repo/requirements.txt

# Run offline unit tests
pytest iac-agents-repo/tests

# Scaffold single module (offline dry-run)
python3 iac-agents-repo/iac_agent/iac_agent.py --request "add an S3 bucket for artifacts" --dry-run

# Multi-module graph decomposition
python3 iac-agents-repo/iac_agent/iac_agent.py --request "stand up VPC and RDS" --graph --dry-run

# Local Platform HTTP API server
python3 iac-agents-repo/iac_agent/iac_agent.py --serve --port 8000

# Display health metrics summary
python3 iac-agents-repo/iac_agent/iac_agent.py --metrics-summary

# Run evaluation suite
python3 iac-agents-repo/iac_agent/iac_agent_eval.py
```
