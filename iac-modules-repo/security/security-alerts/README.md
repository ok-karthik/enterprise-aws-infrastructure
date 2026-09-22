# security/security-alerts

Central alerting for PLAN 4.5. One EventBridge rule per alert type, one encrypted SNS topic, email subscriptions. Which rules are created depends on `var.enable_*` and on **where** the module is applied:

| Rule(s) | `var.enable_*` | Apply in | Why there |
|---|---|---|---|
| `guardduty_finding` | `enable_guardduty_findings` | `security-tooling` | Delegated administrator for GuardDuty (PLAN 4.4): findings land there |
| `securityhub_finding` | `enable_securityhub_findings` | `security-tooling` | Delegated administrator for Security Hub: findings land there |
| `root_console_sign_in`, `root_api_call` | `enable_root_sign_in` | `management` | Root credentials only exist in the management account (PLAN 3.5 removes them everywhere else) |
| `scp_change` | `enable_scp_changes` | `management` | Organizations is only managed centrally |

**BreakGlassAdmin sign-in is already covered** by `security/break-glass-alerts`, applied in every account. This module does not duplicate it.

## What each rule catches

- **`guardduty_finding`**: any GuardDuty finding with `severity >= guardduty_minimum_severity` (default 7.0, GuardDuty's HIGH band).
- **`securityhub_finding`**: any imported Security Hub finding whose severity label is in `securityhub_severity_labels` (default `["HIGH", "CRITICAL"]`). A batch of several findings in one event still raises one alert, using the first finding's detail (EventBridge's input transformer reads one path per field).
- **`root_console_sign_in`**: a console sign-in as the root user.
- **`root_api_call`**: an API call made directly as root, excluding calls an AWS service made on the account's behalf (`userIdentity.invokedBy` must not exist).
- **`scp_change`**: an Organizations policy (SCP, RCP, tag, backup, declarative) created, updated, deleted, attached, detached, or a policy type enabled/disabled.

## Not verified offline

- The exact GuardDuty/Security Hub event shapes (these are documented shapes, not tested against a real finding).
- That EventBridge really receives the CloudTrail-derived events (it does by default when CloudTrail management events are on, which they are).

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
| [aws_cloudwatch_event_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_kms_alias.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_sns_topic.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_enable_guardduty_findings"></a> [enable\_guardduty\_findings](#input\_enable\_guardduty\_findings) | Alert on GuardDuty findings at or above guardduty\_minimum\_severity. Turn on where GuardDuty findings actually land: the delegated administrator account (security-tooling). | `bool` | `false` | no |
| <a name="input_enable_root_sign_in"></a> [enable\_root\_sign\_in](#input\_enable\_root\_sign\_in) | Alert on any sign-in or API call as the account's root user (console or CLI). Root sign-in only matters where<br/>root credentials still exist: the management account (member accounts have theirs removed, PLAN 3.5, and<br/>docs/ROOT\_ACCESS.md's break-glass root tasks are a separate, already-alerted path via security/break-glass-alerts). | `bool` | `false` | no |
| <a name="input_enable_scp_changes"></a> [enable\_scp\_changes](#input\_enable\_scp\_changes) | Alert on Organizations policy changes (SCP/RCP/tag/backup/declarative policy create, update, delete, attach, detach, or a policy type enabled/disabled). Organizations is only managed from the management account, so this only makes sense there. | `bool` | `false` | no |
| <a name="input_enable_securityhub_findings"></a> [enable\_securityhub\_findings](#input\_enable\_securityhub\_findings) | Alert on new Security Hub findings at securityhub\_severity\_labels. Turn on where Security Hub findings land: the delegated administrator account (security-tooling). | `bool` | `false` | no |
| <a name="input_guardduty_minimum_severity"></a> [guardduty\_minimum\_severity](#input\_guardduty\_minimum\_severity) | Minimum GuardDuty finding severity that alerts (GuardDuty's HIGH band starts at 7.0). | `number` | `7` | no |
| <a name="input_kms_deletion_window_days"></a> [kms\_deletion\_window\_days](#input\_kms\_deletion\_window\_days) | Waiting period before a scheduled deletion of the topic's KMS key. | `number` | `30` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every alert resource. | `string` | `"security-alerts"` | no |
| <a name="input_notification_emails"></a> [notification\_emails](#input\_notification\_emails) | Addresses that are told about every alert this module raises. Real, monitored mailboxes. Each address must confirm the SNS subscription once. | `list(string)` | n/a | yes |
| <a name="input_securityhub_severity_labels"></a> [securityhub\_severity\_labels](#input\_securityhub\_severity\_labels) | Security Hub severity labels that alert. | `list(string)` | <pre>[<br/>  "HIGH",<br/>  "CRITICAL"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_enabled_rules"></a> [enabled\_rules](#output\_enabled\_rules) | Names of the EventBridge rules this call created |
| <a name="output_topic_arn"></a> [topic\_arn](#output\_topic\_arn) | ARN of the encrypted SNS topic every alert is published to |
<!-- END_TF_DOCS -->
