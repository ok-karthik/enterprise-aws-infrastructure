# security/access-analyzer

Organization-wide **IAM Access Analyzer**, created in the account that is the **delegated administrator** for `access-analyzer.amazonaws.com` (`security-tooling`; the organization module registers the delegation). Two analyzers cover every account in the organization:

- **External access:** resources (S3 buckets, IAM roles, KMS keys, ...) that can be reached from outside the organization.
- **Unused access:** roles and users with permissions or credentials nobody has used for `unused_access_age_days` (default 90).

Analyzers are regional: apply this in every region in use. **Findings reach Security Hub on their own** once Security Hub is enabled with this account as its delegated administrator (PLAN 4.4); nothing is configured here for that. Unused-access analysis is billed per role analyzed, so it is a paid feature to watch (FINOPS).

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
| [aws_accessanalyzer_analyzer.external](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_analyzer) | resource |
| [aws_accessanalyzer_analyzer.unused](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_analyzer) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_external_analyzer_name"></a> [external\_analyzer\_name](#input\_external\_analyzer\_name) | Name of the organization analyzer for external access (resources shared outside the organization) | `string` | `"org-external-access"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_unused_access_age_days"></a> [unused\_access\_age\_days](#input\_unused\_access\_age\_days) | A role or user counts as unused after this many days without activity, and unused permissions are reported as findings. | `number` | `90` | no |
| <a name="input_unused_analyzer_name"></a> [unused\_analyzer\_name](#input\_unused\_analyzer\_name) | Name of the organization analyzer for unused access | `string` | `"org-unused-access"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_external_analyzer_arn"></a> [external\_analyzer\_arn](#output\_external\_analyzer\_arn) | ARN of the organization analyzer for external access |
| <a name="output_unused_analyzer_arn"></a> [unused\_analyzer\_arn](#output\_unused\_analyzer\_arn) | ARN of the organization analyzer for unused access |
<!-- END_TF_DOCS -->
