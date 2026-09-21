# identity/ack-cross-account

ACK (AWS Controllers for Kubernetes) cross-account trust, applied **per account** (the spoke): the role the hub cluster's ACK controllers assume, a scoped inline policy (S3 buckets with a prefix, IAM roles under a path, only with the `ack-tenant-boundary` permissions boundary), the boundary itself, and the discovery parameter for the role ARN. Split out of `governance/organization`, which is applied in the management account only.

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
| [aws_iam_policy.ack_tenant_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ack_spoke](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ack_spoke_scoped](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.hub_ack_assume_spoke](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_ssm_parameter.ack_cross_account_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ack_role_path"></a> [ack\_role\_path](#input\_ack\_role\_path) | IAM path under which ACK may create roles, without leading slash and with trailing slash (e.g. "ack/"). Scopes iam:CreateRole / PassRole to arn:aws:iam::<account>:role/<path>*. | `string` | `"ack/"` | no |
| <a name="input_ack_s3_bucket_prefix"></a> [ack\_s3\_bucket\_prefix](#input\_ack\_s3\_bucket\_prefix) | Name prefix of the S3 buckets the ACK spoke role may manage (and that ACK-created roles may access). Buckets outside this prefix are out of reach. | `string` | `"platform-ack-"` | no |
| <a name="input_env"></a> [env](#input\_env) | Target environment for discovery contract (e.g. \_global, dev, prod) | `string` | `"_global"` | no |
| <a name="input_external_id"></a> [external\_id](#input\_external\_id) | Shared secret proving the assume-role call is deliberate, preventing confused deputy | `string` | `"platform-ack-shared-secret"` | no |
| <a name="input_hub_account_id"></a> [hub\_account\_id](#input\_hub\_account\_id) | Account ID running the ACK controllers (EKS hub) | `string` | `""` | no |
| <a name="input_hub_ack_controller_role_arn"></a> [hub\_ack\_controller\_role\_arn](#input\_hub\_ack\_controller\_role\_arn) | The IAM role ARN the ACK controller pods assume via Pod Identity in the hub | `string` | `""` | no |
| <a name="input_publish_ssm_parameters"></a> [publish\_ssm\_parameters](#input\_publish\_ssm\_parameters) | Whether to publish discovery contract parameters to SSM Parameter Store | `bool` | `false` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for discovery contract (e.g. eu-central-1) | `string` | `"eu-central-1"` | no |
| <a name="input_spoke_account_id"></a> [spoke\_account\_id](#input\_spoke\_account\_id) | Account ID that owns the actual AWS resources ACK provisions for one team/environment | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ack_cross_account_ssm_parameter"></a> [ack\_cross\_account\_ssm\_parameter](#output\_ack\_cross\_account\_ssm\_parameter) | SSM parameter path for ACK cross-account role ARN |
| <a name="output_ack_tenant_boundary_arn"></a> [ack\_tenant\_boundary\_arn](#output\_ack\_tenant\_boundary\_arn) | ARN of the permissions boundary every ACK-created role must carry |
| <a name="output_spoke_role_arn"></a> [spoke\_role\_arn](#output\_spoke\_role\_arn) | Spoke role ARN assumed by ACK controllers across accounts |
<!-- END_TF_DOCS -->
