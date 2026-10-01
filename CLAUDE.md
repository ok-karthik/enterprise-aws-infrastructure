# CLAUDE.md

This repository maintains a consolidated, framework-agnostic AI agent specification and platform engineering guide in:

👉 **[`AGENTS.md`](AGENTS.md)**

Please refer to [`AGENTS.md`](AGENTS.md) for:
- Repository layout and the Terragrunt inheritance chain architecture
- Essential local and CI commands (smoke test, format, lint, plan)
- Governance gates (OPA/Conftest, Checkov, Infracost; Trivy scans the toolbox image)
- CI/CD workflows and zero-key OIDC authentication
- Conventions and gotchas (`root.hcl` generated files, tag propagation)
- Agent Registry definitions and usage (IaC Architect, Policy Auditor, Pipeline Healer, and IaC Generation Agent)
