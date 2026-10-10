# Changelog

## [3.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/organization-v2.1.0...organization-v3.0.0) (2026-10-10)


### ⚠ BREAKING CHANGES

* **organization:** removed var.allowed_regions (replaced by var.allowed_regions_by_ou, a map keyed by OU name). The live envcommon is updated in this commit; it now also registers security-tooling as the delegated administrator for GuardDuty/Security Hub/Inspector v2/Macie (PLAN 4.4 depended on this and it was missed then).

### Features

* add policy_targets configuration for progressive SCP rollout across OUs ([77ff5c6](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/77ff5c664c23f71f14e420d9b63507098929f8b5))
* **governance,compliance,adrs:** complete offline platform tasks (ADRs, runbooks, compliance, policies, discovery contract) ([ef342e0](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/ef342e04e8180d7df30eab9653453b483239cf37))
* **networking:** hub-and-spoke Phase 5 — IPAM, Transit Gateway, inspection egress, shared endpoints, DNS (PLAN 5.1-5.7) ([e806d7f](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/e806d7f214edf30f5bb80d6749ff7e70c1511d57))
* **organization:** full SCP set, and add governance/data-perimeter for RCPs (PLAN 4.6) ([bf65d19](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/bf65d19a15920fbbdf9f4f016c120f34f111bf48))
* **phase-4:** security baseline, central logging, threat detection & guardrails ([51b654e](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/51b654ef449946a65dd38cb4686456b5f9558c38))
* **platform:** disaster recovery, pipeline hardening, observability, docs, and agent governance (PLAN 7–11) ([8f58efe](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8f58efeb47b7b8127409f3fbd7c02a109258d272))


### Bug Fixes

* **organization:** derive policy attachment for_each keys from static variable map ([f80918d](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/f80918d1edb5a23365fd011c1e60d39e6069355b))
* **organization:** shorten policy description to comply with AWS 512 char limit ([0b3fb66](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/0b3fb66b4f25f8dd805bb584a2aaa0989f5bb105))

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
