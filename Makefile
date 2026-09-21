# Enterprise AWS Platform — task runner
# Wraps the platform's command surface. Run `make help` for the list.

FMT_DIRS := iac-modules-repo foundation-live-repo workloads-live-repo policy-library-repo
ENV ?= dev

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Install the pre-commit hook
	pre-commit install

.PHONY: fmt
fmt: ## Format all HCL/Terraform
	terraform fmt -recursive $(FMT_DIRS)
	terragrunt hcl fmt

.PHONY: fmt-check
fmt-check: ## Check formatting (CI gate)
	terraform fmt -check -recursive $(FMT_DIRS)

.PHONY: lint
lint: ## Run TFLint recursively
	tflint --init
	tflint --recursive --format=compact

.PHONY: validate
validate: ## Full local validation suite (compliance, fmt, init/validate, tflint)
	./workloads-live-repo/scripts/smoke-test.sh

.PHONY: security
security: ## Trivy security scan of the repo
	trivy config . --severity CRITICAL,HIGH --ignorefile .trivyignore --tf-exclude-downloaded-modules

.PHONY: plan
plan: ## Plan one workload account: make plan ENV=dev (folder workloads-live-repo/workloads-<ENV>)
	cd workloads-live-repo/workloads-$(ENV) && terragrunt run --all plan --non-interactive

.PHONY: test
test: ## Run OPA policy unit tests and module unit tests (no AWS credentials needed)
	conftest verify --policy policy-library-repo/terraform
	@for d in iac-modules-repo/*/*/tests; do \
		[ -d "$$d" ] || continue; \
		m=$$(dirname "$$d"); echo "-> $$m"; \
		(cd "$$m" && terraform init -backend=false -input=false >/dev/null && terraform test) || exit 1; \
	done

.PHONY: docs
docs: ## Regenerate per-module terraform-docs READMEs
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/network/vpc
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/compute/eks
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/data/postgres
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/storage/s3
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/identity/workload-iam
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/identity/human-access
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/identity/workload-identity
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/governance/organization
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/governance/bootstrap-stacksets
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/identity/ack-cross-account
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/governance/account-factory
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/governance/account-baseline
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/governance/discovery-publisher
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/governance/budgets
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/identity/identity-center
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/security/break-glass-alerts
