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

.PHONY: checkov
checkov: ## Checkov with the CI settings (.checkov.yaml); the same result as the CI check
	./workloads-live-repo/scripts/run-checkov.sh --compact --quiet

.PHONY: image-scan
image-scan: ## Build the toolbox image and scan it with Trivy (needs Docker), like publish-toolchain.yml
	docker build -t infrastructure-toolchain:scan -f .github/docker/Dockerfile .
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		public.ecr.aws/aquasecurity/trivy:$$(sed -n 's/^ARG TRIVY_VERSION=//p' .github/docker/Dockerfile | head -n 1) \
		image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 infrastructure-toolchain:scan

.PHONY: verify-module
verify-module: ## Check ONE module with the CI tools, no AWS credentials: make verify-module MODULE=storage/s3
	@test -n "$(MODULE)" || { echo "usage: make verify-module MODULE=<category/name>"; exit 2; }
	@mkdir -p "$${TF_PLUGIN_CACHE_DIR:-$$HOME/.terraform.d/plugin-cache}"
	TF_PLUGIN_CACHE_DIR="$${TF_PLUGIN_CACHE_DIR:-$$HOME/.terraform.d/plugin-cache}" python3 workloads-live-repo/scripts/verify_module.py $(MODULE) $(VERIFY_ARGS)

.PHONY: plan
plan: ## Plan one workload account: make plan ENV=nonprod/workloads-dev
	cd workloads-live-repo/workloads/$(ENV) && terragrunt run --all plan --non-interactive --log-format bare

.PHONY: test
test: ## Run OPA policy unit tests, module unit tests and Python unit tests (no AWS credentials needed)
	conftest verify --policy policy-library-repo/terraform
	@for d in iac-modules-repo/*/*/tests; do \
		[ -d "$$d" ] || continue; \
		m=$$(dirname "$$d"); echo "-> $$m"; \
		(cd "$$m" && terraform init -backend=false -input=false >/dev/null && terraform test) || exit 1; \
		ls "$$d"/test_*.py >/dev/null 2>&1 && (cd "$$m" && python3 -m unittest discover -s tests) || true; \
	done
	@echo "-> iac-agents-repo tests"
	python3 -m unittest discover -s iac-agents-repo/tests
	python3 -m unittest discover -s .agents/tests

.PHONY: docs
docs: ## Regenerate per-module terraform-docs READMEs
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/network/vpc
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/network/ipam
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/network/transit-gateway
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/network/tgw-attachment
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/network/tgw-peering
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/network/inspection-egress
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/network/central-endpoints
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/network/dns
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
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/security/access-analyzer
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/security/log-archive
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/security/org-cloudtrail
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/security/threat-detection
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/security/security-alerts
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/governance/data-perimeter
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/security/auto-remediation
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/edge/cloudfront
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/security/firewall-manager
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/security/waf-logging
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/security/shield-advanced
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/data/aurora-postgres
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/data/backup
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/network/route53-failover
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/governance/billing
	terraform-docs markdown table --output-file README.md --output-mode inject iac-modules-repo/observability/guardrail-signals
