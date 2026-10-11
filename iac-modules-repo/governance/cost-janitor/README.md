# governance/cost-janitor

**Status:** 📝 Plan-only (wired into the dev leaf; not applied to AWS)

A weekly Lambda (EventBridge Scheduler, Mondays 06:00 Europe/Berlin) that finds orphaned, billable resources in one
account and region (PLAN 9.5). **Report-only by default.** Meant for dev, never prod.

| Finds | Rule |
|---|---|
| Unattached EBS volumes | status `available` for at least `volume_min_age_days` (14) |
| Old EBS snapshots | owned by this account, at least `snapshot_min_age_days` (30) old; snapshots used by an own AMI and AWS Backup snapshots (`aws:backup:` tag) are skipped |
| Unassociated Elastic IPs | no association |
| Log groups without retention | skipped when the name starts with one of `exclude_log_group_prefixes` |

Each run logs one JSON line (`dry_run`, the found IDs, `kept`, `errors`, `estimated_monthly_usd`) to the Lambda's log
group, and publishes a short text version to `alert_topic_arn` when it is set. The estimate uses approximate
eu-central-1 list prices (gp3 $0.08/GB, other volumes $0.10/GB, snapshots $0.05/GB, Elastic IP $3.60/month); treat it as a rough number.

## Safety

- **`keep=true` opt-out.** A resource tagged `keep=true` is never touched. The code lists it under `kept`; in act mode IAM
  also refuses the delete (`StringNotEquals aws:ResourceTag/keep = true`). Log groups have no such tag, use `exclude_log_group_prefixes`.
- **No delete permission in dry-run mode.** The `cost-janitor-act` policy (`ec2:DeleteVolume`, `ec2:DeleteSnapshot`,
  `ec2:ReleaseAddress`, `logs:PutRetentionPolicy`) exists only when `dry_run = false`.
- One failed delete does not stop the others; failures are listed under `errors`.

## Switching to act mode

1. Apply with `dry_run = true` and read at least one weekly summary in CloudWatch Logs.
2. Tag anything you want to keep with `keep=true`.
3. Set `dry_run = false`, apply, and read the next summary.

Logs created outside Terraform (Lambda, EKS add-ons) are the reason for the retention fix; code we write is already covered by Checkov `CKV_AWS_66`.

## Tests

`make verify-module MODULE=governance/cost-janitor` (Terraform) and `python3 -m unittest discover -s tests` from this folder (Python, hand-written fake clients, no boto3).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.4 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.8.1 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.68.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.act](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_function.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_scheduler_schedule.weekly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [archive_file.lambda](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alert_topic_arn"></a> [alert\_topic\_arn](#input\_alert\_topic\_arn) | Optional SNS topic that gets a short text version of each run. null = only the CloudWatch Logs summary. | `string` | `null` | no |
| <a name="input_default_log_retention_days"></a> [default\_log\_retention\_days](#input\_default\_log\_retention\_days) | Retention set on log groups that have none (only when dry\_run = false). Must be a value CloudWatch Logs accepts. | `number` | `30` | no |
| <a name="input_dry_run"></a> [dry\_run](#input\_dry\_run) | true = only report. false = delete unattached volumes, old snapshots and unassociated Elastic IPs, and set retention on log groups without one. The delete permissions exist in IAM only when this is false, and never apply to resources tagged keep=true. | `bool` | `true` | no |
| <a name="input_exclude_log_group_prefixes"></a> [exclude\_log\_group\_prefixes](#input\_exclude\_log\_group\_prefixes) | Log groups whose name starts with one of these are ignored | `list(string)` | `[]` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention of the Lambda's own log group | `number` | `30` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the Lambda, its role, its log group and its schedule | `string` | `"cost-janitor"` | no |
| <a name="input_schedule_expression"></a> [schedule\_expression](#input\_schedule\_expression) | EventBridge Scheduler expression for the run | `string` | `"cron(0 6 ? * MON *)"` | no |
| <a name="input_schedule_timezone"></a> [schedule\_timezone](#input\_schedule\_timezone) | Time zone of schedule\_expression | `string` | `"Europe/Berlin"` | no |
| <a name="input_snapshot_min_age_days"></a> [snapshot\_min\_age\_days](#input\_snapshot\_min\_age\_days) | An EBS snapshot owned by this account is reported (or deleted) only when it is at least this old. Snapshots used by an AMI and AWS Backup snapshots are always skipped. | `number` | `30` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_volume_min_age_days"></a> [volume\_min\_age\_days](#input\_volume\_min\_age\_days) | An unattached EBS volume is reported (or deleted) only when it is at least this old | `number` | `14` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_dry_run"></a> [dry\_run](#output\_dry\_run) | Whether the janitor only reports |
| <a name="output_function_arn"></a> [function\_arn](#output\_function\_arn) | ARN of the janitor Lambda |
| <a name="output_function_name"></a> [function\_name](#output\_function\_name) | Name of the janitor Lambda |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Log group that holds the one-line JSON summary of each run |
<!-- END_TF_DOCS -->
