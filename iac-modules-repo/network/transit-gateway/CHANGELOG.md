# Changelog

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/transit-gateway-v1.0.0...transit-gateway-v2.0.0) (2026-10-10)


### ⚠ BREAKING CHANGES

* **transit-gateway:** network/transit-gateway no longer has the peering input or the peering_attachment_id output. Use network/tgw-peering instead.

### Features

* **networking:** hub-and-spoke Phase 5 — IPAM, Transit Gateway, inspection egress, shared endpoints, DNS (PLAN 5.1-5.7) ([e806d7f](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/e806d7f214edf30f5bb80d6749ff7e70c1511d57))
* **platform:** disaster recovery, pipeline hardening, observability, docs, and agent governance (PLAN 7–11) ([8f58efe](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8f58efeb47b7b8127409f3fbd7c02a109258d272))
* **transit-gateway:** hub-and-spoke Transit Gateway, cross-region peering, hybrid connectivity (PLAN 5.2, 5.6) ([1e2c2fb](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/1e2c2fba24deeac7dd901e8ba7ec23e0e37d7350))


### Code Refactoring

* **transit-gateway:** move cross-region peering into network/tgw-peering ([ae85088](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/ae85088e9311a7407d8d1a0a5f18d26542782595))
