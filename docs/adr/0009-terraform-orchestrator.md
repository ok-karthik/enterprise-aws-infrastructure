# ADR 0009: Terraform CI/CD Orchestration: GitHub Actions vs Digger vs Atlantis vs Paid SaaS

- Status: accepted
- Date: 2026-09-29

## Context

Running Terraform and Terragrunt in a collaborative engineering team requires automating plan previews on Pull Requests, posting plan comments, enforcing policy gates, and applying approved changes upon merge.

The team evaluated four deployment and orchestration architectures:
1. Native GitHub Actions workflows
2. Digger (in-repo / in-action orchestrator)
3. Atlantis (self-hosted server)
4. Paid SaaS platforms (Spacelift, env0, Terraform Cloud / HCP Terraform)

## Decision

1. **Primary Orchestrator: Native GitHub Actions + Zero-Key OIDC**:
   - The repository uses native GitHub Actions (`.github/workflows/terragrunt.yml` and `reusable-terragrunt.yml`).
   - Authentication is strictly zero-key AWS IAM OIDC directly into the target account (no static AWS secrets, no cross-account role chaining).
   - Plan-stage OPA/Conftest, Checkov, and Infracost checks run as native parallel jobs.
   - Deterministic apply is achieved by uploading binary plans (`planbin-*`) and verifying SHA256 manifests upon merge.
2. **Designated Next-Tier Target: Digger**:
   - If interactive ChatOps (`digger plan` / `digger apply`) and fine-grained project concurrency are required beyond native Actions, **Digger** is the designated recommendation.

## What I chose against and what it cost

- **Atlantis**:
  - *Why rejected*: Atlantis requires maintaining, patching, and securing an always-on public server with broad AWS credentials into all accounts. An unpatched vulnerability in Atlantis exposes the entire cloud infrastructure. It introduces a single point of failure and operational toil.
- **Paid SaaS (Spacelift / env0 / HCP Terraform)**:
  - *Why rejected*: Recurring subscription costs ($200–$1,000+/month), vendor lock-in, and compliance friction regarding third-party SaaS systems receiving sensitive plan outputs and infrastructure state files.
- **Cost of Native GitHub Actions**:
  - Requires maintaining workflow YAML and custom plan-upload/binary-apply caching logic.
  - Mitigated by composite actions (`.github/actions/setup-platform/action.yml`) and Docker toolchain containerization (`ghcr.io/ok-karthik/infrastructure-toolchain:latest`).

## Consequences

- Zero external infrastructure to host, monitor, or patch.
- Zero licensing costs.
- Fully auditable CI runs integrated directly into GitHub Pull Request reviews and branch protections.
