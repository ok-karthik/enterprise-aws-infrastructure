# observability/guardrail-signals

"Are the guardrails still on?" (PLAN 9.3). Each signal is a CloudTrail event that means a control was weakened,
counted by a CloudWatch Logs metric filter and alarmed on the **first** occurrence:

| Signal | Event |
|---|---|
| `CloudTrailTampering` | `StopLogging`, `DeleteTrail`, `UpdateTrail`, `PutEventSelectors` |
| `ConfigRecorderStopped` | `StopConfigurationRecorder`, `DeleteConfigurationRecorder`, `DeleteDeliveryChannel` |
| `GuardDutyDisabled` | `DeleteDetector`, `DisableOrganizationAdminAccount`, `StopMonitoringMembers`, `DisassociateFromMasterAccount` |
| `SecurityHubDisabled` | `DisableSecurityHub`, `DisableOrganizationAdminAccount`, `BatchDisableStandards` |
| `RootUsage` | any API call by the root user (not made by an AWS service) |
| `BreakGlassUsage` | any API call by a `BreakGlassAdmin` session |

The organization CloudTrail records every member account, so **one application in the management account covers the
whole organization**. The alarms and metric filters live where the trail's CloudWatch log group is
(`security/org-cloudtrail`'s `cloudwatch_log_group_name` output).

## Two ways to apply it

1. **Management account** (`create_alarms = true`, default): metric filters and alarms, pointing `alarm_topic_arn` at the
   security-alerts topic.
2. **Observability account** (`create_alarms = false`, `create_dashboard = true`, `metrics_account_id = <management id>`):
   only the dashboard, reading the management account's metrics through cross-account observability
   (`observability/oam`, with the management account linked to the sink).

## Things to know

- The metric filters only see events **after** they are created; nothing is back-filled.
- A filter matches events from all accounts and regions the trail covers, but the alarm does not say *which* account:
  open the filter's log group in CloudWatch Logs Insights and filter on `recipientAccountId`.
- `BreakGlassUsage` will fire on every legitimate break-glass session. That is the point (`docs/BREAK_GLASS.md`).
- Not covered: CloudTrail delivery failures and long-open drift. See `docs/SLO.md` for why and where they are tracked.

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

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_dashboard.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) | resource |
| [aws_cloudwatch_log_metric_filter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter) | resource |
| [aws_cloudwatch_metric_alarm.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alarm_topic_arn"></a> [alarm\_topic\_arn](#input\_alarm\_topic\_arn) | SNS topic that receives the alarms (for example the security-alerts topic). Empty = alarms exist but notify nobody. | `string` | `""` | no |
| <a name="input_create_alarms"></a> [create\_alarms](#input\_create\_alarms) | Create the metric filters and alarms. True where the organization trail's CloudWatch log group lives (the management account); false in an account that only shows the dashboard. | `bool` | `true` | no |
| <a name="input_create_dashboard"></a> [create\_dashboard](#input\_create\_dashboard) | Create the one dashboard 'guardrails are working'. Normally applied in the observability account. | `bool` | `false` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | CloudWatch log group that receives the organization CloudTrail (the cloudwatch\_log\_group\_name output of security/org-cloudtrail). Required when create\_alarms is true. | `string` | `""` | no |
| <a name="input_metrics_account_id"></a> [metrics\_account\_id](#input\_metrics\_account\_id) | Dashboard only: the account that owns the metrics (the one with create\_alarms = true). Read through cross-account observability (observability/oam). Empty = this account. | `string` | `""` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for alarm and dashboard names | `string` | `"platform-guardrails"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alarm_arns"></a> [alarm\_arns](#output\_alarm\_arns) | ARNs of the guardrail alarms (empty when create\_alarms is false) |
| <a name="output_dashboard_name"></a> [dashboard\_name](#output\_dashboard\_name) | Name of the dashboard. Empty unless create\_dashboard is true. |
| <a name="output_signal_names"></a> [signal\_names](#output\_signal\_names) | Names of the signals (metric names in the Platform/Guardrails namespace) |
<!-- END_TF_DOCS -->
