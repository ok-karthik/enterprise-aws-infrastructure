# ADR 0010: Terragrunt vs Plain Terraform / OpenTofu

- Status: superseded by ADR 0009
- Date: 2026-09-29

## Context

In industry hiring statistics, Terraform appears in ~49% of infrastructure engineering job advertisements, while Terragrunt appears in ~2%. Using Terragrunt requires explicit architectural justification to demonstrate that its benefits outweigh the added tooling layer, while ensuring that the underlying Terraform modules remain fully usable by standard Terraform tools.

A multi-account, multi-region AWS enterprise foundation involves managing dozens of interconnected components (VPCs, EKS clusters, databases, IAM roles, log buckets) across multiple environments (`dev`, `staging`, `prod`) and accounts (`management`, `log-archive`, `security-tooling`, `network-hub`, `workloads`).

## Decision

1. **Adopt Terragrunt as a Lightweight Configuration Wrapper**:
   - Terragrunt is used strictly for environment orchestration, DRY backend/provider generation (`generate` blocks in `root.hcl`), and dependency graph execution (`run --all`).
2. **Pure, Standard Terraform in `iac-modules-repo/`**:
   - All modules in `iac-modules-repo/` are written in **100% pure standard Terraform**. They contain zero Terragrunt constructs, no hardcoded provider blocks, and no backend configurations.
   - Any external team or tenant can consume the modules directly using plain Terraform or OpenTofu via standard Git module sources.
3. **Layered Inheritance (`_envcommon`)**:
   - Common configuration blueprints live in `_envcommon/`, ensuring that environment leaf directories only declare local overrides.

## What I chose against and what it cost

- **Pure Terraform with Workspaces**:
  - *Why rejected*: Terraform workspaces share backend configuration, variable definitions, and state file locations. A bug in workspace configuration risks accidentally running `destroy` against production. Workspaces lack native multi-account authentication and cross-component dependency ordering.
- **Pure Terraform with Duplicated Root Modules**:
  - *Why rejected*: Copying `main.tf`, `variables.tf`, and `outputs.tf` across every environment and account leads to massive code duplication and configuration drift. Updating an EKS module across 10 accounts requires editing 10 separate boilerplate files.
- **Cost of Terragrunt**:
  - Requires maintaining the Terragrunt binary in local and CI toolchains.
  - Learning curve for developers unfamiliar with Terragrunt's `read_terragrunt_config` and `dependency` blocks.

## Consequences

- 100% DRY infrastructure definitions across all accounts and regions.
- Zero boilerplate: `provider.tf` and `backend.tf` are dynamically generated at plan time with deterministic S3 state keys and default tags.
- Full compatibility with the broader Terraform ecosystem: modules remain pure Terraform.
