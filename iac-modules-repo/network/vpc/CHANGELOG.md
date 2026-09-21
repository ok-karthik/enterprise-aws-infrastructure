# Changelog

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/vpc-vv1.0.0...vpc-vv2.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* **modules:** module source paths changed from infrastructure-modules/... to iac-modules-repo/.... Tags created before this commit (for example vpc-v1.0.0) point at the old path; release each module again so tags exist at the new path before pinning anything to them (PLAN 1.4).

### Bug Fixes

* **security:** suppress CKV2_AWS_34 for non-sensitive SSM discovery contract parameters ([3b3a487](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/3b3a487901feeabf21c3ce9d0f614db9967a6cdc))


### Code Refactoring

* **modules:** move infrastructure-modules to iac-modules-repo ([2d794a7](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/2d794a763811591760017ca6de9be999bbb5848c))
