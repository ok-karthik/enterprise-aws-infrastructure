# data/backup

AWS Backup for one region (PLAN 7.3): an encrypted vault, a daily plan, a tag-based selection, and an optional
**cross-region copy** of every recovery point to a vault in the secondary region.

## How it fits together

1. In the **secondary region**, apply this module with `create_plan = false` and that region's own KMS key.
   It creates only the vault. Take its `vault_arn` output.
2. In the **primary region**, apply it with `copy_destination_vault_arn = <that ARN>`. The plan then copies each
   daily recovery point across.
3. Tenants opt in by tagging a resource `Backup = true` (change with `selection_tag_key` / `selection_tag_value`).

## Things to know

- The vault policy denies deleting recovery points to everyone except a `<name>-break-glass` role. It is not
  Backup Vault Lock (compliance mode cannot be undone, so it is a separate, deliberate decision).
- A copy needs the destination vault's KMS key to allow the AWS Backup service role of the source account.
- Cross-region copies cost storage in both regions plus data transfer: see `FINOPS.md`.
- The org already has `BACKUP_POLICY` enabled (`governance/organization`); this module is the per-account,
  per-region building block that such a policy would target.

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
| [aws_backup_plan.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan) | resource |
| [aws_backup_selection.tagged](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection) | resource |
| [aws_backup_vault.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_backup_vault_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_policy) | resource |
| [aws_iam_role.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_copy_destination_vault_arn"></a> [copy\_destination\_vault\_arn](#input\_copy\_destination\_vault\_arn) | Optional (PLAN 7.3): ARN of the vault in another region that receives a copy of every recovery point. Create it first, with this module in the secondary region (create\_plan = false). Empty = no cross-region copy. | `string` | `""` | no |
| <a name="input_copy_retention_days"></a> [copy\_retention\_days](#input\_copy\_retention\_days) | Days the cross-region copy is kept | `number` | `35` | no |
| <a name="input_create_plan"></a> [create\_plan](#input\_create\_plan) | Create the backup plan and tag selection. Set false in a region that only holds a copy destination vault. | `bool` | `true` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Customer-managed KMS key in THIS region that encrypts the vault. A vault cannot share a key across regions, so the secondary region needs its own. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the vault, plan and role (for example platform-prod) | `string` | n/a | yes |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Days a recovery point in this region is kept | `number` | `35` | no |
| <a name="input_schedule"></a> [schedule](#input\_schedule) | Cron expression (UTC) for the daily backup | `string` | `"cron(0 3 * * ? *)"` | no |
| <a name="input_selection_tag_key"></a> [selection\_tag\_key](#input\_selection\_tag\_key) | Resources carrying this tag key with the value selection\_tag\_value are backed up. Tag-based, so tenants opt in without touching this stack. | `string` | `"Backup"` | no |
| <a name="input_selection_tag_value"></a> [selection\_tag\_value](#input\_selection\_tag\_value) | Value of the selection tag | `string` | `"true"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags for the vault, plan and role | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_plan_id"></a> [plan\_id](#output\_plan\_id) | Backup plan ID. Empty when create\_plan is false. |
| <a name="output_vault_arn"></a> [vault\_arn](#output\_vault\_arn) | ARN of the backup vault in this region (pass it as copy\_destination\_vault\_arn to the primary region's stack) |
| <a name="output_vault_name"></a> [vault\_name](#output\_vault\_name) | Name of the backup vault in this region |
<!-- END_TF_DOCS -->
