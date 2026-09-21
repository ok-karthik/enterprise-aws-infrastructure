# governance/budgets

Budgets from day one, applied in **every** account: a monthly cost budget with alerts at **50 / 80 / 100 % of the actual** spend and **100 % of the forecast**, and a Cost Anomaly Detection monitor (per service, daily email). It protects the sandbox bill as much as production.

- The amount (`monthly_budget_usd`) and the alert address (the account's `email`) come from the account registry `foundation-live-repo/_config/accounts.hcl`. In the **management account** (the payer) the budget covers the whole organization, so keep it low (default 50 USD) while nothing runs. AWS Budgets reports in USD.
- The module refuses an `@example.com` address, so a placeholder fails at plan time instead of alerting nobody.
- Optional `notification_sns_topic_arns` also receive the alerts (the topic policy must allow `budgets.amazonaws.com`).

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
| [aws_budgets_budget.monthly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |
| [aws_ce_anomaly_monitor.services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_monitor) | resource |
| [aws_ce_anomaly_subscription.daily](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_subscription) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_name"></a> [account\_name](#input\_account\_name) | Account name from the registry. Used in budget and monitor names. | `string` | n/a | yes |
| <a name="input_anomaly_threshold"></a> [anomaly\_threshold](#input\_anomaly\_threshold) | Cost Anomaly Detection: report an anomaly when its total impact is at least this amount (in the budget currency). | `number` | `10` | no |
| <a name="input_currency"></a> [currency](#input\_currency) | Budget currency. AWS Budgets is billed and reported in USD. | `string` | `"USD"` | no |
| <a name="input_monthly_limit"></a> [monthly\_limit](#input\_monthly\_limit) | Monthly cost budget for this account. In the management account (the payer) it covers the whole organization, so keep it low while nothing runs. | `number` | n/a | yes |
| <a name="input_notification_emails"></a> [notification\_emails](#input\_notification\_emails) | Addresses that receive budget alerts and anomaly reports. Real, monitored mailboxes: an alert nobody reads is no alert. | `list(string)` | n/a | yes |
| <a name="input_notification_sns_topic_arns"></a> [notification\_sns\_topic\_arns](#input\_notification\_sns\_topic\_arns) | Optional SNS topics that also receive the budget alerts. The topic policy must allow budgets.amazonaws.com to publish. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_anomaly_monitor_arn"></a> [anomaly\_monitor\_arn](#output\_anomaly\_monitor\_arn) | ARN of the Cost Anomaly Detection monitor |
| <a name="output_budget_name"></a> [budget\_name](#output\_budget\_name) | Name of the monthly cost budget |
<!-- END_TF_DOCS -->
