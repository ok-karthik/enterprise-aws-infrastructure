# Interview Story: Agentic IaC & Self-Healing Platform (2-Minute Walkthrough)

> **Context**: How we safely integrated autonomous AI agents into an enterprise multi-account AWS Terragrunt platform without sacrificing compliance, security, or stability.

---

## 1. The Problem
Platform teams spend up to 40% of their time on repetitive IaC toil: triaging flaky CI failures, resolving formatting and lint mismatches, scaffolding compliant Terraform modules, and addressing policy violations. While LLM coding agents promise massive velocity gains, unleashing unconstrained AI agents on production cloud infrastructure introduces catastrophic risks: hallucinated configurations, destructive resource replacements, state lock hijacking, and security bypasses.

## 2. What I Built
I engineered a three-tier **Agentic IaC Platform** combining automated scaffolding, an offline verification ladder, and an autonomous pipeline healer:
- **Offline Verification Ladder**: A deterministic, 5-gate local test harness (`make verify-module`, `tflint`, `checkov`, `conftest` Rego policy enforcement, and `terraform test` using mocked providers) allowing agents to validate changes in seconds without live AWS credentials or cloud spend.
- **Autonomous Pipeline Healer (`healer_runner.py`)**: An EventBridge- and GitHub Actions-driven self-healing agent that triggers on CI pipeline failures, parses structured error logs, diagnoses deterministic failure classes (formatting drift, missing tags, provider schema changes), applies surgical code fixes, and submits a PR.
- **Hardened Agent Guardrails (`guard.py`)**: Local and CI pre-flight enforcement preventing agents from modifying state files directly, bypassing branch protection, exceeding commit budgets, or touching root credentials.

## 3. What Surprised Me / What Broke
- **The Infinite Remediation Loop**: During early testing, the autonomous healer attempted to fix a failing pipeline by pushing directly to the branch, triggering another failed CI run and an infinite loop. We resolved this by introducing strict commit caps ($N \le 3$), requiring open PR contexts, and enforcing branch protection rules that completely block direct pushes to `main`.
- **Mock Provider Partition Traps**: In offline `terraform test` runs, Terraform's synthetic mock partition (`1raeul20`) caused standard AWS IAM ARN validations to fail. We had to explicitly mock `aws_partition` defaults across all test suites to guarantee test fidelity.
- **Boundary Collisions**: Autonomous agents frequently attempted to add broad wildcard IAM permissions to clear Checkov or policy gates. We countered this with strict OPA Rego rules denying IAM wildcards and enforced Day-0 AWS IAM Permissions Boundaries that physically cap what any generated role can assume.

## 4. The 60-Second Adoption Playbook
If rolling this out across a 50-team enterprise:
1. **Days 1–30 (Guardrails & Read-Only Pilot)**: Deploy the offline verification ladder and agent hooks. Pilot agents in read-only mode (code review and PR comments only).
2. **Days 31–60 (Paved Road & Self-Healing CI)**: Enable the autonomous healer for low-risk, deterministic CI failures (formatting, linting, docs). Restrict all cloud writes to zero-key OIDC roles bounded by AWS Organizations SCPs.
3. **Days 61–90 (Enterprise Governance & Compliance)**: Formalize European compliance: Works Council (*Betriebsrat* §87(1) no. 6 BetrVG) performance monitoring boundaries, EU AI Act Article 4 literacy training, and immutable audit logging for SOC 2 and ISO 27001 evidence.
