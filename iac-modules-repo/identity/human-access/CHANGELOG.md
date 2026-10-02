# Changelog

## [3.1.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/human-access-v3.0.0...human-access-v3.1.0) (2026-10-02)


### Features

* **platform:** disaster recovery, pipeline hardening, observability, docs, and agent governance (PLAN 7–11) ([8f58efe](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8f58efeb47b7b8127409f3fbd7c02a109258d272))

## [3.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/human-access-v2.0.0...human-access-v3.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* **human-access:** the permission sets, their variables (sso_instance_arn, name_prefix, session_duration, break_glass_session_duration, permissions_boundary_arn) and outputs are removed. No live stack used them.

### Features

* **human-access:** move the Identity Center permission sets to identity-center ([4a9dead](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/4a9dead7cbb3780c7d6b09190b47978211b8209a))
* **phase-3:** identity, least privilege, break-glass alerts & access analyzer ([6f96cd0](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/6f96cd0cac5ceafd67aab1549adb259587cf3363))

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/human-access-v1.0.0...human-access-v2.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* **modules:** module source paths changed from infrastructure-modules/... to iac-modules-repo/.... Tags created before this commit (for example vpc-v1.0.0) point at the old path; release each module again so tags exist at the new path before pinning anything to them (PLAN 1.4).

### Code Refactoring

* **modules:** move infrastructure-modules to iac-modules-repo ([2d794a7](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/2d794a763811591760017ca6de9be999bbb5848c))
