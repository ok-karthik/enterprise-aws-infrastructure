# governance/account-baseline

Applied to **every** account (management, workloads, ...), in its primary region. The state bucket, the OIDC provider and the CI roles are **not** here: they come from the Day-0 bootstrap (CloudFormation / StackSets), because this module needs them before it can run.

- **`platform-workload-boundary`**: the permissions boundary every role created by Terraform, ACK or tenants must carry. One broad Allow, then Denies: a role under it can only create roles with the same boundary (so it cannot be shed), cannot remove or edit the boundary, create IAM users or access keys, edit `platform-*` / `terraform-*` / `github-actions-*` roles, tamper with CloudTrail / Config / GuardDuty / Security Hub / Access Analyzer / Macie, lower the account defaults below, or touch Organizations and Identity Center.
- **Account defaults:** IAM account alias (optional), a strict IAM password policy, S3 account-level Block Public Access, EBS encryption by default, IMDSv2 as the default (both regional), and VPC Block Public Access (`enable_vpc_block_public_access`, on by default, PLAN 5.7) — a VPC excludes its own public subnets explicitly (`network/vpc`'s `exclude_public_subnets_from_account_bpa`) rather than this default being turned off.
- **KMS:** one CMK per data class (`alias/platform-general`, `alias/platform-confidential`) with rotation on.
- **`security-remediation`** (`security_remediation_lambda_role_arn`, PLAN 4.9): when given the `security/auto-remediation` Lambda's execution role ARN, creates a narrow role in this account that only that Lambda may assume, scoped to describing/revoking security group ingress and tagging the group it touched.
- **Discovery contract, account dimension** (`publish_ssm_parameters`): `/platform/<env>/<region>/account/{id,ou}`, `.../kms/{general,confidential}_key_arn` and `.../iam/workload_boundary_arn`. See `docs/DISCOVERY_CONTRACT.md`.

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
| [aws_ebs_encryption_by_default.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_encryption_by_default) | resource |
| [aws_ec2_instance_metadata_defaults.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_instance_metadata_defaults) | resource |
| [aws_iam_account_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_account_alias) | resource |
| [aws_iam_account_password_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_account_password_policy) | resource |
| [aws_iam_policy.developer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.workload_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.security_remediation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.security_remediation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kms_alias.confidential](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.general](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.confidential](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.general](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_account_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_account_public_access_block) | resource |
| [aws_ssm_parameter.discovery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_vpc_block_public_access_options.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_block_public_access_options) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_alias"></a> [account\_alias](#input\_account\_alias) | IAM account alias (globally unique, lowercase). Leave empty to skip the alias. | `string` | `""` | no |
| <a name="input_enable_vpc_block_public_access"></a> [enable\_vpc\_block\_public\_access](#input\_enable\_vpc\_block\_public\_access) | Block internet gateway traffic account-wide by default (PLAN 5.7). A VPC that genuinely needs a public subnet excludes it explicitly (network/vpc's exclude\_public\_subnets\_from\_account\_bpa), never by turning this off. | `bool` | `true` | no |
| <a name="input_env"></a> [env](#input\_env) | Environment of this account (dev, staging, prod, global). Used in the discovery parameter names. | `string` | n/a | yes |
| <a name="input_kms_deletion_window_days"></a> [kms\_deletion\_window\_days](#input\_kms\_deletion\_window\_days) | Waiting period before a scheduled KMS key deletion. | `number` | `30` | no |
| <a name="input_ou"></a> [ou](#input\_ou) | Name of the OU this account is in. Published as a discovery parameter. | `string` | n/a | yes |
| <a name="input_password_policy_min_length"></a> [password\_policy\_min\_length](#input\_password\_policy\_min\_length) | Minimum IAM password length. IAM users are discouraged (Identity Center is the human path), this is the floor if one exists. | `number` | `14` | no |
| <a name="input_publish_ssm_parameters"></a> [publish\_ssm\_parameters](#input\_publish\_ssm\_parameters) | Publish the account and KMS discovery parameters (/platform/<env>/<region>/account/*, .../kms/*). | `bool` | `true` | no |
| <a name="input_region"></a> [region](#input\_region) | Region this module is applied in. Regional settings (EBS encryption, IMDSv2 default, KMS keys) apply to this region only. | `string` | n/a | yes |
| <a name="input_security_remediation_lambda_role_arn"></a> [security\_remediation\_lambda\_role\_arn](#input\_security\_remediation\_lambda\_role\_arn) | ARN of the security/auto-remediation Lambda's execution role (PLAN 4.9), applied in security-tooling.<br/>When set, creates a narrow security-remediation role in THIS account that only that Lambda may assume, to<br/>revoke open SSH/RDP security group rules. Empty (the default) creates nothing: leave it empty until the<br/>Lambda exists and security-tooling has a real account id. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | ID of the account this baseline was applied to |
| <a name="output_developer_policy_name"></a> [developer\_policy\_name](#output\_developer\_policy\_name) | Name of the customer-managed policy the Developer permission set attaches (it must exist in every assigned account) |
| <a name="output_discovery_parameter_names"></a> [discovery\_parameter\_names](#output\_discovery\_parameter\_names) | Names of the discovery parameters published in this account |
| <a name="output_kms_confidential_key_arn"></a> [kms\_confidential\_key\_arn](#output\_kms\_confidential\_key\_arn) | ARN of the CMK for confidential data |
| <a name="output_kms_general_key_arn"></a> [kms\_general\_key\_arn](#output\_kms\_general\_key\_arn) | ARN of the CMK for general (internal) data |
| <a name="output_security_remediation_role_arn"></a> [security\_remediation\_role\_arn](#output\_security\_remediation\_role\_arn) | ARN of the security-remediation role, or null when security\_remediation\_lambda\_role\_arn is empty |
| <a name="output_workload_boundary_arn"></a> [workload\_boundary\_arn](#output\_workload\_boundary\_arn) | ARN of platform-workload-boundary, which every role created by Terraform, ACK or tenants must carry |
<!-- END_TF_DOCS -->
