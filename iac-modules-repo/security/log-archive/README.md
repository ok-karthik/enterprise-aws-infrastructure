# security/log-archive

The central **log archive** (PLAN 4.1), applied in the `log-archive` account. It creates one S3 bucket per log type and one KMS key:

| Log type | Bucket | Written by |
|---|---|---|
| `cloudtrail` | `<prefix>-cloudtrail-<account id>-<region>` | the organization trail (`security/org-cloudtrail`) |
| `config` | `<prefix>-config-...` | AWS Config |
| `vpc_flow_logs` | `<prefix>-vpc-flow-logs-...` | VPC flow logs |
| `waf` | `aws-waf-logs-<prefix>-...` (WAF requires this prefix) | WAF logging |
| `alb_access` | `<prefix>-alb-access-...` | ALB access logs |
| `cloudfront_access` | `<prefix>-cloudfront-access-...` | CloudFront standard logging |
| `state_access` | `<prefix>-state-access-...` | S3 server access logs of the `tg-state-*` buckets |

The bucket names are a **contract**: the `org-cloudtrail` leaf builds the same CloudTrail bucket name from the same prefix, so the trail can be created in the management account without reading this stack's state.

## What protects the logs

- **Object Lock, `COMPLIANCE` mode.** Nobody, not even the account root, can delete or overwrite a log before its retention ends. Retention is `retention_days` per log type (CloudTrail and Config 400 days, the rest 90). **COMPLIANCE cannot be undone:** if you apply this by mistake, the objects stay (and are billed) until retention ends. Use `object_lock_mode = "GOVERNANCE"` while experimenting in a sandbox.
- **Lifecycle:** logs with a retention longer than `glacier_transition_days` (default 90) move to Glacier, and expire `expire_after_retention_days` (30) after the lock ends, never before.
- **Encryption:** one customer-managed KMS key (rotation on) for every type that S3 can encrypt with KMS. ALB access logs and S3 server access logs only support SSE-S3, so those two buckets use it (this is the one inline Checkov skip on encryption).
- **Bucket policies:** each bucket only allows the AWS service that delivers that log type, and only for this organization (`aws:SourceOrgID`); the CloudTrail bucket only accepts the organization trail (`aws:SourceArn`). Non-TLS requests are denied. Public access is blocked and ACLs are disabled (`BucketOwnerEnforced`).

## Cost

Storage only (cents for a sandbox), plus one KMS key (about $1 a month). Object Lock adds no charge.

## Not verified offline

Only a real delivery proves these, so check each with the first apply (PLAN 4.1 owner step):

- That each service accepts an `aws:SourceOrgID` condition on its delivery. If a delivery is denied, look at the bucket policy first.
- The ALB delivery principal for your region (`alb_log_delivery_principal_arns`).
- The key policy statements for CloudTrail (`kms:EncryptionContext:aws:cloudtrail:arn`) and Config.
- CloudFront standard logging (v2) delivers through `delivery.logs.amazonaws.com`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.65.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kms_alias.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_object_lock_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.sse_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_log_delivery_principal_arns"></a> [alb\_log\_delivery\_principal\_arns](#input\_alb\_log\_delivery\_principal\_arns) | IAM principals that deliver ALB access logs. Regions opened before August 2022 use a regional ELB account (the default is the<br/>one for eu-central-1). For a newer region set this to [] and the policy uses the service principal<br/>logdelivery.elasticloadbalancing.amazonaws.com instead. Check the current AWS documentation for your region. | `list(string)` | <pre>[<br/>  "arn:aws:iam::054676820928:root"<br/>]</pre> | no |
| <a name="input_enabled_log_types"></a> [enabled\_log\_types](#input\_enabled\_log\_types) | Which log buckets to create. | `list(string)` | <pre>[<br/>  "cloudtrail",<br/>  "config",<br/>  "vpc_flow_logs",<br/>  "waf",<br/>  "alb_access",<br/>  "cloudfront_access",<br/>  "state_access"<br/>]</pre> | no |
| <a name="input_expire_after_retention_days"></a> [expire\_after\_retention\_days](#input\_expire\_after\_retention\_days) | Delete objects (and old versions) this many days after the Object Lock retention ends. | `number` | `30` | no |
| <a name="input_glacier_transition_days"></a> [glacier\_transition\_days](#input\_glacier\_transition\_days) | Move objects to Glacier after this many days. A log type whose retention is not longer than this is not transitioned. | `number` | `90` | no |
| <a name="input_kms_deletion_window_days"></a> [kms\_deletion\_window\_days](#input\_kms\_deletion\_window\_days) | Waiting period before a scheduled deletion of the KMS key. | `number` | `30` | no |
| <a name="input_management_account_id"></a> [management\_account\_id](#input\_management\_account\_id) | 12-digit ID of the management account: the organization trail is created there and writes to AWSLogs/<this id>/. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every bucket. Bucket names are <prefix>-<log type>-<account id>-<region> (the WAF bucket is aws-waf-logs-<prefix>-...): the org-cloudtrail leaf builds the same name, so they are a contract. | `string` | `"platform"` | no |
| <a name="input_object_lock_mode"></a> [object\_lock\_mode](#input\_object\_lock\_mode) | COMPLIANCE (nobody can shorten or remove the lock, the audit setting) or GOVERNANCE (a privileged principal can bypass it). COMPLIANCE cannot be undone: objects stay, and are billed, until retention ends. | `string` | `"COMPLIANCE"` | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | ID of the AWS Organization (o-xxxxxxxxxx). Every delivery bucket policy only lets AWS services write when aws:SourceOrgID is this organization. | `string` | n/a | yes |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Object Lock retention in days per log type. Objects cannot be deleted or overwritten before this, not even by<br/>the account root, when object\_lock\_mode is COMPLIANCE. CloudTrail and Config default to 400 days (SOC 2 / ISO 27001<br/>evidence, see docs/COMPLIANCE.md); the rest to 90. Types missing from the map use 90. | `map(number)` | <pre>{<br/>  "cloudtrail": 400,<br/>  "config": 400<br/>}</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_trail_home_region"></a> [trail\_home\_region](#input\_trail\_home\_region) | Home region of the organization trail. Empty means the region this module is applied in. | `string` | `""` | no |
| <a name="input_trail_name"></a> [trail\_name](#input\_trail\_name) | Name of the organization trail (the org-cloudtrail module). The CloudTrail bucket policy only accepts writes from this trail. | `string` | `"platform-org-trail"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_arns"></a> [bucket\_arns](#output\_bucket\_arns) | Log type => bucket ARN |
| <a name="output_bucket_names"></a> [bucket\_names](#output\_bucket\_names) | Log type => bucket name |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key that encrypts the logs (the org trail is given this ARN) |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms\_key\_id) | ID of the KMS key that encrypts the logs |
<!-- END_TF_DOCS -->
