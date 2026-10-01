# governance/billing

**Status:** 📝 Plan-only (wired into `foundation-live-repo`; not applied to AWS)

Billing foundation for the management (payer) account (PLAN 9.2):

| What | Resource | Notes |
|---|---|---|
| Cost data | CUR 2.0 **Data Export** to an S3 bucket (daily, Parquet, with resource IDs) | Read it with Athena. Bucket is private, versioned, TLS-only, writable only by the billing services for this account |
| Anomaly alerts | Cost Anomaly Detection: one monitor for the whole organization by service, plus **one per OU** by linked account | One daily email summary above a USD threshold |
| Showback | `aws_ce_cost_allocation_tag` for the tag keys you list (start with `CostCenter`) | Makes the tag a column in the CUR and Cost Explorer |

Per-account budgets are `governance/budgets` (PLAN 2.8); this module is about *seeing* the cost, not capping it.

## Things to know

- **Second provider.** The Data Exports API only exists in `us-east-1` and its resource has no `region` argument, so the
  module needs `providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }`. The live leaf generates that alias.
- **Cost allocation tags** can only be activated after a resource with that tag key has shown up in billing data
  (up to 24 h after tagging). Leave `cost_allocation_tags` empty on the first apply, then add `["CostCenter"]`.
- **Anomaly emails must be real.** The module refuses `@example.com`, so it will not plan until the owner sets a real address.
- The SCP region allow-list does not apply to the management account, and `ce:*` and `cur:*` are exempt anyway.
- Nothing here was applied. Numbers for `docs/FINOPS.md` need a real payer account and a month of data.

## Showback query (Athena, after the export has run)

```sql
-- Monthly unblended cost by CostCenter tag, top 20. Table = your Glue/Athena table over s3://<bucket>/cur2/.
SELECT line_item_usage_account_id AS account,
       resource_tags['user_costcenter'] AS cost_center,
       round(sum(line_item_unblended_cost), 2) AS usd
FROM   cur2
WHERE  billing_period = '2026-10'
GROUP  BY 1, 2
ORDER  BY usd DESC
LIMIT  20;
```

(CUR 2.0 stores tag columns as a map, `resource_tags`, with `user_` prefixed keys. Check the exact column name in your
table before relying on the query.)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.66.0 |
| <a name="provider_aws.us_east_1"></a> [aws.us\_east\_1](#provider\_aws.us\_east\_1) | 6.66.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_bcmdataexports_export.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bcmdataexports_export) | resource |
| [aws_ce_anomaly_monitor.ou](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_monitor) | resource |
| [aws_ce_anomaly_monitor.services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_monitor) | resource |
| [aws_ce_anomaly_subscription.daily](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_subscription) | resource |
| [aws_ce_cost_allocation_tag.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_cost_allocation_tag) | resource |
| [aws_s3_bucket.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_anomaly_alert_emails"></a> [anomaly\_alert\_emails](#input\_anomaly\_alert\_emails) | Who gets the daily anomaly summary. At least one address. | `list(string)` | n/a | yes |
| <a name="input_anomaly_ou_accounts"></a> [anomaly\_ou\_accounts](#input\_anomaly\_ou\_accounts) | OU name => list of 12-digit account IDs in it. One Cost Anomaly Detection monitor is created per OU (only accounts with real IDs; leave placeholders out). The organization-wide per-service monitor is always created. | `map(list(string))` | `{}` | no |
| <a name="input_anomaly_threshold_usd"></a> [anomaly\_threshold\_usd](#input\_anomaly\_threshold\_usd) | Alert when an anomaly's total impact is at least this many US dollars. | `number` | `20` | no |
| <a name="input_cost_allocation_tags"></a> [cost\_allocation\_tags](#input\_cost\_allocation\_tags) | Tag keys to activate for cost allocation (they then appear in the CUR and Cost Explorer, which is what the CostCenter showback needs). A key can only be activated after a resource with it has been seen in billing data (up to 24 hours after tagging), so leave this empty until then. | `list(string)` | `[]` | no |
| <a name="input_export_retention_days"></a> [export\_retention\_days](#input\_export\_retention\_days) | Days the CUR files are kept in the bucket. Billing data is needed for audits for years, so the default keeps 13 months hot and expires after that; archive elsewhere if you must keep more. | `number` | `400` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the export and the bucket (for example platform-billing) | `string` | `"platform-billing"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for the bucket and the monitors | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_anomaly_monitor_arns"></a> [anomaly\_monitor\_arns](#output\_anomaly\_monitor\_arns) | ARNs of all anomaly monitors (the organization-wide one and one per OU) |
| <a name="output_cur_bucket_name"></a> [cur\_bucket\_name](#output\_cur\_bucket\_name) | Bucket that receives the CUR 2.0 export (point Athena at s3://<bucket>/cur2/) |
| <a name="output_export_arn"></a> [export\_arn](#output\_export\_arn) | ARN of the Data Exports export |
<!-- END_TF_DOCS -->
