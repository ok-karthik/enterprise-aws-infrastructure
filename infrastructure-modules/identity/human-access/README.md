<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
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
| [aws_eks_access_entry.team](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.team_view](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_ssoadmin_managed_policy_attachment.auditor_security](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_managed_policy_attachment) | resource |
| [aws_ssoadmin_managed_policy_attachment.developer_view](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_managed_policy_attachment) | resource |
| [aws_ssoadmin_managed_policy_attachment.platform_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_managed_policy_attachment) | resource |
| [aws_ssoadmin_permission_set.auditor](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_ssoadmin_permission_set.developer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_ssoadmin_permission_set.platform_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster to grant access entries for | `string` | `""` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix prepended to permission set names (e.g. Enterprise, Dev, Prod) | `string` | `"Enterprise"` | no |
| <a name="input_session_duration"></a> [session\_duration](#input\_session\_duration) | The length of time that the application user sessions are valid (e.g. PT4H, PT8H, PT12H) | `string` | `"PT8H"` | no |
| <a name="input_sso_instance_arn"></a> [sso\_instance\_arn](#input\_sso\_instance\_arn) | The Amazon Resource Name (ARN) of the IAM Identity Center instance (leave empty if managing cluster access entries only) | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_team_access"></a> [team\_access](#input\_team\_access) | Map of (team, tier) access configurations with principal ARN and kubernetes groups | <pre>map(object({<br/>    principal_arn = string<br/>    k8s_groups    = list(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_entry_arns"></a> [access\_entry\_arns](#output\_access\_entry\_arns) | Map of EKS Access Entry ARNs created for teams |
| <a name="output_auditor_permission_set_arn"></a> [auditor\_permission\_set\_arn](#output\_auditor\_permission\_set\_arn) | The ARN of the AuditorReadOnly permission set |
| <a name="output_developer_permission_set_arn"></a> [developer\_permission\_set\_arn](#output\_developer\_permission\_set\_arn) | The ARN of the Developer permission set |
| <a name="output_platform_admin_permission_set_arn"></a> [platform\_admin\_permission\_set\_arn](#output\_platform\_admin\_permission\_set\_arn) | The ARN of the PlatformAdmin permission set |
<!-- END_TF_DOCS -->