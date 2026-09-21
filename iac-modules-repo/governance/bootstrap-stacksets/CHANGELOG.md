# Changelog

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/bootstrap-stacksets-v1.0.0...bootstrap-stacksets-v2.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* **live:** state keys change (dev/... becomes workloads-dev/..., _global/... becomes management/_global/...) and the workload buckets follow the workload accounts. Nothing was applied, so there is no state to move.
* **policy:** policies/terraform is now policy-library-repo/terraform.
* **live:** infrastructure-live/ and infrastructure-bootstrap/ no longer exist. Workflow working directories, script paths and bootstrap.sh moved (foundation-live-repo/_bootstrap/bootstrap.sh).
* **modules:** module source paths changed from infrastructure-modules/... to iac-modules-repo/.... Tags created before this commit (for example vpc-v1.0.0) point at the old path; release each module again so tags exist at the new path before pinning anything to them (PLAN 1.4).

### Code Refactoring

* **live:** account-first layout, env from account.hcl, stricter registry check ([79ae036](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/79ae036cfa2e3f686f778faa70f3e0c7b62370d0))
* **live:** split infrastructure-live and infrastructure-bootstrap into foundation and workloads repos ([4851fd2](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/4851fd253ca68b2934fe294e3037c5bf58405f3f))
* **modules:** move infrastructure-modules to iac-modules-repo ([2d794a7](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/2d794a763811591760017ca6de9be999bbb5848c))
* **policy:** move policies to policy-library-repo ([38fa317](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/38fa317d811f9b731c92a4a8dc863544ca42de02))
