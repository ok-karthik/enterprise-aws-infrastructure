# Changelog

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/data-perimeter-v1.0.0...data-perimeter-v2.0.0) (2026-09-22)


### ⚠ BREAKING CHANGES

* **organization:** removed var.allowed_regions (replaced by var.allowed_regions_by_ou, a map keyed by OU name). The live envcommon is updated in this commit; it now also registers security-tooling as the delegated administrator for GuardDuty/Security Hub/Inspector v2/Macie (PLAN 4.4 depended on this and it was missed then).

### Features

* **organization:** full SCP set, and add governance/data-perimeter for RCPs (PLAN 4.6) ([bf65d19](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/bf65d19a15920fbbdf9f4f016c120f34f111bf48))
* **phase-4:** security baseline, central logging, threat detection & guardrails ([51b654e](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/51b654ef449946a65dd38cb4686456b5f9558c38))
