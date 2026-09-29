# AWS Config Organization Governance Module

Manages AWS Config organization-wide compliance and resource inventory across multi-account AWS landing zones (PLAN 4.3).

## Features
- **Regional Recorder & Delivery**: Configures AWS Config recorders and delivery channels pointing to the central compliance S3 bucket in `log-archive`.
- **Multi-Account Aggregator**: Deployed in `security-tooling` (delegated administrator) to aggregate configuration items and compliance states across all member accounts and allowed regions.
- **Organization Conformance Packs**:
  - Operational Best Practices for CIS AWS Foundations Benchmark v1.4
  - Operational Best Practices for NIST 800-53 rev 5
  - Operational Best Practices for AICPA SOC 2

## Usage

```hcl
module "org_config" {
  source = "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/org-config?ref=org-config-v1.0.0"

  is_primary_region           = true
  allowed_regions             = ["eu-central-1", "eu-west-1"]
  config_delivery_bucket_name = "tg-log-archive-config-111122223333"

  enable_cis_conformance_pack         = true
  enable_nist_800_53_conformance_pack = true
  enable_soc2_conformance_pack        = true
}
```
