# security/org-cloudtrail

The organization-wide **CloudTrail** (PLAN 4.2): one trail, applied **once** in the management account, that logs every account (`is_organization_trail = true`, `is_multi_region_trail = true`). It delivers to the bucket that `security/log-archive` builds in the `log-archive` account.

## The naming contract

This module and `security/log-archive` never read each other's state. They agree on names instead:

- `log_archive_bucket_name` must equal that module's `bucket_names["cloudtrail"]` output (`<name_prefix>-cloudtrail-<log-archive account id>-<region>`), which the `_envcommon` blueprint computes from the account registry.
- `trail_name` (default `platform-org-trail`) must equal the `trail_name` the log-archive bucket policy trusts.

If the names drift apart, the trail either fails to deliver or the bucket policy denies it. Both are checked by the first apply, not by Terraform.

## What it creates

- The trail itself: log file validation on, encrypted with the log-archive KMS key (`kms_key_arn`), delivering to S3.
- **CloudWatch Logs delivery**: a log group (`/aws/cloudtrail/<trail name>`), a service role CloudTrail assumes to write to it, and a KMS key **local to the management account** (CloudWatch Logs needs a key in its own account and region; it cannot use the cross-account log-archive key). This makes the trail queryable in near-real-time with metric filters and alarms, on top of the S3 copy.
- **SNS notifications** of each log file delivery (`CKV_AWS_252`), on the same local key. This is CloudTrail's own "a file was delivered" notice, not a security alert channel — that is `security/break-glass-alerts` and the EventBridge rules in PLAN 4.5.
- **Optional S3 data events**, for buckets tagged `DataClassification = confidential` (`confidential_s3_bucket_arns`). Terraform cannot discover tagged buckets across accounts by itself, so this list is populated by hand (or a future automated collector) — leaving it empty logs management events only, which is also the trail's implicit default.
- **Optional CloudTrail Lake** (`enable_cloudtrail_lake`), an organization event data store for SQL queries over trail events.

## Not verified offline

- That `is_organization_trail = true` succeeds when applied (it must be created in the **management** account, and needs organization trusted access for `cloudtrail.amazonaws.com`, already in `governance/organization`'s default `aws_service_access_principals`).
- That the log-archive bucket policy actually accepts this trail's deliveries (the two modules' names must match; a real delivery is the only proof).
- The exact `resources.ARN` matching CloudTrail expects for S3 data events (`<bucket arn>/`, one advanced event selector clause per bucket) once a real confidential bucket exists.

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
| [aws_cloudtrail.org](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail) | resource |
| [aws_cloudtrail_event_data_store.org](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail_event_data_store) | resource |
| [aws_cloudwatch_log_group.org_trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.cloudtrail_to_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cloudtrail_to_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kms_alias.trail_support](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.trail_support](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_sns_topic.trail_notifications](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.trail_notifications](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloudtrail_lake_retention_days"></a> [cloudtrail\_lake\_retention\_days](#input\_cloudtrail\_lake\_retention\_days) | Retention (days) of the CloudTrail Lake event data store, when enabled. | `number` | `400` | no |
| <a name="input_cloudwatch_log_retention_days"></a> [cloudwatch\_log\_retention\_days](#input\_cloudwatch\_log\_retention\_days) | Retention (days) of the /aws/cloudtrail/<trail name> CloudWatch Logs group. Must be one of the values CloudWatch Logs accepts. | `number` | `400` | no |
| <a name="input_confidential_s3_bucket_arns"></a> [confidential\_s3\_bucket\_arns](#input\_confidential\_s3\_bucket\_arns) | S3 bucket ARNs tagged DataClassification=confidential (docs/DISCOVERY\_CONTRACT.md, account-baseline's general/confidential<br/>key split): the trail logs S3 data events (object-level reads and writes) for these buckets. Terraform cannot discover<br/>tagged buckets across accounts by itself, so this is populated by hand or by a future automated collector. Empty means<br/>only management events are logged (the trail's default), which is also what a trail with no advanced\_event\_selector does. | `list(string)` | `[]` | no |
| <a name="input_enable_cloudtrail_lake"></a> [enable\_cloudtrail\_lake](#input\_enable\_cloudtrail\_lake) | Also create a CloudTrail Lake organization event data store, for SQL queries over trail events without exporting to S3/Athena. | `bool` | `false` | no |
| <a name="input_kms_deletion_window_days"></a> [kms\_deletion\_window\_days](#input\_kms\_deletion\_window\_days) | Waiting period before a scheduled deletion of the CloudWatch Logs / SNS KMS key (not the log-archive key, which this module does not create). | `number` | `30` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the log-archive KMS key (security/log-archive output kms\_key\_arn) that encrypts the trail's log files. | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Name of the CloudTrail bucket in the log-archive account (security/log-archive output bucket\_names["cloudtrail"]; the two modules share the naming contract, so this can be computed without reading that module's state). | `string` | n/a | yes |
| <a name="input_s3_key_prefix"></a> [s3\_key\_prefix](#input\_s3\_key\_prefix) | Key prefix inside the log-archive bucket. Empty means none. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_trail_name"></a> [trail\_name](#input\_trail\_name) | Name of the organization trail. Must match the name the log-archive bucket policy trusts (security/log-archive var.trail\_name). | `string` | `"platform-org-trail"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloudtrail_lake_arn"></a> [cloudtrail\_lake\_arn](#output\_cloudtrail\_lake\_arn) | ARN of the CloudTrail Lake event data store, or null when enable\_cloudtrail\_lake is false |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the CloudWatch Logs group the trail delivers to |
| <a name="output_home_region"></a> [home\_region](#output\_home\_region) | Region the trail was created in (its home region; the trail itself covers every region) |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | ARN of the SNS topic that receives CloudTrail's log-delivery notifications |
| <a name="output_trail_arn"></a> [trail\_arn](#output\_trail\_arn) | ARN of the organization trail |
| <a name="output_trail_name"></a> [trail\_name](#output\_trail\_name) | Name of the organization trail |
<!-- END_TF_DOCS -->
