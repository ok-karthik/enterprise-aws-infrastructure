# Changelog

## [2.1.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/s3-v2.0.0...s3-v2.1.0) (2026-10-10)


### Features

* **agents:** verify-module, guard hooks, healer limits, autonomy levels, adoption draft (PLAN 11.1 to 11.6) ([750f072](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/750f07225afd69ba9cd671030ef58329613ea3a2))
* **aurora-postgres:** add Aurora Global Database, S3 replication and AWS Backup copy (PLAN 7.3) ([45a3b78](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/45a3b78b53d5070df0906fc8e9adbc0b89e4208b))
* **platform:** disaster recovery, pipeline hardening, observability, docs, and agent governance (PLAN 7–11) ([8f58efe](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8f58efeb47b7b8127409f3fbd7c02a109258d272))


### Bug Fixes

* **tflint:** add aws required_providers constraint in basic examples ([52ff292](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/52ff292ce1fbaaf6ae131c57d05dfcc6cd67825f))

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/s3-v1.0.0...s3-v2.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* **modules:** module source paths changed from infrastructure-modules/... to iac-modules-repo/.... Tags created before this commit (for example vpc-v1.0.0) point at the old path; release each module again so tags exist at the new path before pinning anything to them (PLAN 1.4).

### Code Refactoring

* **modules:** move infrastructure-modules to iac-modules-repo ([2d794a7](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/2d794a763811591760017ca6de9be999bbb5848c))
