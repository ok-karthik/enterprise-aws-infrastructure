# Changelog

## [2.1.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/postgres-v2.0.0...postgres-v2.1.0) (2026-10-10)


### Features

* **pipeline:** retire trivy config, prune duplicate Rego, add observability and billing (PLAN 8.3, 8.4, 8.9, 8.10, 9.1, 9.2) ([8fe5216](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8fe5216ca8ad9ac0bec19a691e38c61304160032))
* **platform:** disaster recovery, pipeline hardening, observability, docs, and agent governance (PLAN 7–11) ([8f58efe](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8f58efeb47b7b8127409f3fbd7c02a109258d272))

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/postgres-v1.0.0...postgres-v2.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* **modules:** module source paths changed from infrastructure-modules/... to iac-modules-repo/.... Tags created before this commit (for example vpc-v1.0.0) point at the old path; release each module again so tags exist at the new path before pinning anything to them (PLAN 1.4).

### Code Refactoring

* **modules:** move infrastructure-modules to iac-modules-repo ([2d794a7](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/2d794a763811591760017ca6de9be999bbb5848c))
