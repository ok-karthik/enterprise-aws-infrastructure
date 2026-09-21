# Changelog

## [2.1.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/organization-v2.0.0...organization-v2.1.0) (2026-09-21)


### Features

* **organization:** enable centralized root access and register delegated administrators ([501ecfb](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/501ecfbf5eb45498720732f47f43836cb8f96d17))
* **phase-3:** identity, least privilege, break-glass alerts & access analyzer ([6f96cd0](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/6f96cd0cac5ceafd67aab1549adb259587cf3363))

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/organization-v1.0.0...organization-v2.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* **organization:** the Production/NonProduction OUs, the root_id input and the ACK inputs and outputs are removed (ACK is now identity/ack-cross-account). The organization must be imported before the first apply.
* **modules:** module source paths changed from infrastructure-modules/... to iac-modules-repo/.... Tags created before this commit (for example vpc-v1.0.0) point at the old path; release each module again so tags exist at the new path before pinning anything to them (PLAN 1.4).

### Features

* **organization:** manage the organization, a nested OU tree and baseline SCPs ([64db335](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/64db3350f8c362d5ab2b307354cd502bb56eda59))


### Code Refactoring

* **modules:** move infrastructure-modules to iac-modules-repo ([2d794a7](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/2d794a763811591760017ca6de9be999bbb5848c))
