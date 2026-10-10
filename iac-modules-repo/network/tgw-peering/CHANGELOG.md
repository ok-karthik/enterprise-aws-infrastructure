# Changelog

## [2.0.0](https://github.com/ok-karthik/enterprise-aws-infrastructure/compare/tgw-peering-v1.0.0...tgw-peering-v2.0.0) (2026-10-10)


### ⚠ BREAKING CHANGES

* **transit-gateway:** network/transit-gateway no longer has the peering input or the peering_attachment_id output. Use network/tgw-peering instead.

### Features

* **platform:** disaster recovery, pipeline hardening, observability, docs, and agent governance (PLAN 7–11) ([8f58efe](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/8f58efeb47b7b8127409f3fbd7c02a109258d272))


### Code Refactoring

* **transit-gateway:** move cross-region peering into network/tgw-peering ([ae85088](https://github.com/ok-karthik/enterprise-aws-infrastructure/commit/ae85088e9311a7407d8d1a0a5f18d26542782595))
