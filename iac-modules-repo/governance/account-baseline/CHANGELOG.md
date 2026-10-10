# Changelog

## [1.2.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/account-baseline-v1.1.0...account-baseline-v1.2.0) (2026-10-10)


### Features

* **auto-remediation:** remove open SSH/RDP security group rules automatically (PLAN 4.9) ([2d41208](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/2d41208db99aa9d467abb15407b2a334a2769a39))
* **networking:** hub-and-spoke Phase 5 — IPAM, Transit Gateway, inspection egress, shared endpoints, DNS (PLAN 5.1-5.7) ([e806d7f](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/e806d7f214edf30f5bb80d6749ff7e70c1511d57))
* **phase-4:** security baseline, central logging, threat detection & guardrails ([51b654e](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/51b654ef449946a65dd38cb4686456b5f9558c38))
* **pipeline:** retire trivy config, prune duplicate Rego, add observability and billing (PLAN 8.3, 8.4, 8.9, 8.10, 9.1, 9.2) ([8fe5216](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8fe5216ca8ad9ac0bec19a691e38c61304160032))
* **platform:** disaster recovery, pipeline hardening, observability, docs, and agent governance (PLAN 7–11) ([8f58efe](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8f58efeb47b7b8127409f3fbd7c02a109258d272))
* **vpc:** flow logs to S3, and account-wide VPC Block Public Access (PLAN 5.7) ([77f14df](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/77f14df713f2ed8903d3b85593621b9e5ef0a3ae))

## [1.1.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/account-baseline-v1.0.0...account-baseline-v1.1.0) (2026-09-21)


### Features

* **account-baseline:** add the platform-developer policy behind the Developer permission set ([ac369ce](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/ac369ce191de640710729b9b60dfb4490cc2f6bc))
* **phase-3:** identity, least privilege, break-glass alerts & access analyzer ([6f96cd0](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/6f96cd0cac5ceafd67aab1549adb259587cf3363))


### Bug Fixes

* **account-baseline:** deny only public Lambda function URLs in the Developer policy ([ab0ce21](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/ab0ce21c04fd185dd074d7fa99048e3c02e5bcc8))
* **account-baseline:** deny resource-policy writes and cross-team SSM in the Developer policy, skip the rest with reasons ([a3208b6](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/a3208b6660875782533922d2800db6fd8318f500))
* let the management apply role manage Identity Center (3.8) and deny only public Lambda URLs (3.7) ([9ed70ae](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/9ed70aea1f921bc554f8e9c3b53f9054ed48a3ae))

## 1.0.0 (2026-09-21)


### Features

* **account-baseline:** add the per-account baseline module ([d2e84cf](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/d2e84cf26f1be94a0abd0e58b91de5eef626e6fb))
