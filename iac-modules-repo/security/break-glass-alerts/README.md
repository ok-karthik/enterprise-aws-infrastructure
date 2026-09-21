# security/break-glass-alerts

Tells people about every **BreakGlassAdmin** sign-in: EventBridge rules for the ways to sign in (STS `AssumeRoleWithSAML` in the account, console sign-in, and in the management account also the Identity Center portal calls, which are the only events that show CLI sign-ins), an SNS topic **encrypted with its own rotating KMS key**, and an email subscription per address. Regional: applied in every account, in the primary region. Part of the just-in-time access design, see [`docs/BREAK_GLASS.md`](../../../docs/BREAK_GLASS.md).

- Only the module's own rules may publish to the topic (`aws:SourceArn`), and only they may use the key.
- Each address has to **confirm the SNS subscription** once, or it receives nothing.
- The module refuses an `@example.com` address, so a registry placeholder fails at plan time.
- Cross-account forwarding to the security-tooling account and Slack/PagerDuty come with PLAN 4.5.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.66.0 |

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
| <a name="input_enable_sso_portal_rule"></a> [enable\_sso\_portal\_rule](#input\_enable\_sso\_portal\_rule) | Also alert on the IAM Identity Center portal calls (Federate / GetRoleCredentials). These are the only events<br/>that show CLI sign-ins, and they are logged in the MANAGEMENT account, so turn this on there and nowhere else. | `bool` | `false` | no |
| <a name="input_kms_deletion_window_days"></a> [kms\_deletion\_window\_days](#input\_kms\_deletion\_window\_days) | Waiting period before a scheduled deletion of the topic's KMS key. | `number` | `30` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of the alert resources | `string` | `"break-glass"` | no |
| <a name="input_notification_emails"></a> [notification\_emails](#input\_notification\_emails) | Addresses that are told about every break-glass sign-in. Real, monitored mailboxes. Each address must confirm the SNS subscription once. | `list(string)` | n/a | yes |
| <a name="input_permission_set_name"></a> [permission\_set\_name](#input\_permission\_set\_name) | Name of the break-glass permission set in Identity Center. Its roles are named AWSReservedSSO\_<name>\_<hash>. | `string` | `"BreakGlassAdmin"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_rule_names"></a> [rule\_names](#output\_rule\_names) | Names of the EventBridge rules |
| <a name="output_topic_arn"></a> [topic\_arn](#output\_topic\_arn) | ARN of the break-glass alert topic |
<!-- END_TF_DOCS -->
