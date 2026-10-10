# Changelog

## [3.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/vpc-v2.0.0...vpc-v3.0.0) (2026-10-10)


### ⚠ BREAKING CHANGES

* **ipam:** add the org-wide IPAM and wire network/vpc to request from it (PLAN 5.1)

### Features

* **governance,compliance,adrs:** complete offline platform tasks (ADRs, runbooks, compliance, policies, discovery contract) ([ef342e0](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/ef342e04e8180d7df30eab9653453b483239cf37))
* **inspection-egress:** central egress VPC with AWS Network Firewall (PLAN 5.3) ([cd0ed38](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/cd0ed38c7f345a22dfcc425aaf9e2935fed1c228))
* **ipam:** add the org-wide IPAM and wire network/vpc to request from it (PLAN 5.1) ([d4e948e](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/d4e948e8b1b36523aae8c9c5779cba22ebcf3014))
* **networking:** hub-and-spoke Phase 5 — IPAM, Transit Gateway, inspection egress, shared endpoints, DNS (PLAN 5.1-5.7) ([e806d7f](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/e806d7f214edf30f5bb80d6749ff7e70c1511d57))
* **platform:** disaster recovery, pipeline hardening, observability, docs, and agent governance (PLAN 7–11) ([8f58efe](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8f58efeb47b7b8127409f3fbd7c02a109258d272))
* **vpc:** flow logs to S3, and account-wide VPC Block Public Access (PLAN 5.7) ([77f14df](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/77f14df713f2ed8903d3b85593621b9e5ef0a3ae))

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/vpc-v1.0.0...vpc-v2.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* **modules:** module source paths changed from infrastructure-modules/... to iac-modules-repo/.... Tags created before this commit (for example vpc-v1.0.0) point at the old path; release each module again so tags exist at the new path before pinning anything to them (PLAN 1.4).

### Bug Fixes

* **security:** suppress CKV2_AWS_34 for non-sensitive SSM discovery contract parameters ([3b3a487](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/3b3a487901feeabf21c3ce9d0f614db9967a6cdc))


### Code Refactoring

* **modules:** move infrastructure-modules to iac-modules-repo ([2d794a7](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/2d794a763811591760017ca6de9be999bbb5848c))
