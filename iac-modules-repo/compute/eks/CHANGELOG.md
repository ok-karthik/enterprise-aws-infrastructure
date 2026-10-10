# Changelog

## [2.1.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/eks-v2.0.0...eks-v2.1.0) (2026-10-10)


### Features

* **governance,compliance,adrs:** complete offline platform tasks (ADRs, runbooks, compliance, policies, discovery contract) ([ef342e0](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/ef342e04e8180d7df30eab9653453b483239cf37))
* **platform:** disaster recovery, pipeline hardening, observability, docs, and agent governance (PLAN 7–11) ([8f58efe](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8f58efeb47b7b8127409f3fbd7c02a109258d272))

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/eks-v1.0.0...eks-v2.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* **policy:** policies/terraform is now policy-library-repo/terraform.
* **modules:** module source paths changed from infrastructure-modules/... to iac-modules-repo/.... Tags created before this commit (for example vpc-v1.0.0) point at the old path; release each module again so tags exist at the new path before pinning anything to them (PLAN 1.4).

### Bug Fixes

* **security:** suppress CKV2_AWS_34 for non-sensitive SSM discovery contract parameters ([3b3a487](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/3b3a487901feeabf21c3ce9d0f614db9967a6cdc))


### Code Refactoring

* **modules:** move infrastructure-modules to iac-modules-repo ([2d794a7](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/2d794a763811591760017ca6de9be999bbb5848c))
* **policy:** move policies to policy-library-repo ([38fa317](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/38fa317d811f9b731c92a4a8dc863544ca42de02))
