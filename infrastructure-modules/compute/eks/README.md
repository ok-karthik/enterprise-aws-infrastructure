# compute/eks

Reusable EKS module wrapping `terraform-aws-modules/eks/aws`. Encrypts Kubernetes secrets with a dedicated KMS key and enables full control-plane logging (api, audit, authenticator, controllerManager, scheduler) by default, so clusters are auditable and encrypted at rest out of the box.

## Inputs

| Name | Description | Type | Default |
| :--- | :--- | :--- | :--- |
| `cluster_name` | Name of the EKS cluster | `string` | n/a |
| `kubernetes_version` | Kubernetes version to use | `string` | `"1.30"` |
| `vpc_id` | VPC ID where the cluster will be deployed | `string` | n/a |
| `subnet_ids` | A list of subnet IDs where the EKS nodes will be deployed | `list(string)` | n/a |
| `min_size` | Minimum number of nodes | `number` | `1` |
| `max_size` | Maximum number of nodes | `number` | `3` |
| `desired_size` | Desired number of nodes | `number` | `1` |
| `instance_types` | List of instance types for the node group | `list(string)` | `["t4g.small", "t4g.medium"]` |
| `tags` | A map of tags to add to all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
| :--- | :--- |
| `cluster_arn` | The Amazon Resource Name (ARN) of the cluster |
| `cluster_certificate_authority_data` | Base64 encoded certificate data required to communicate with the cluster |
| `cluster_endpoint` | Endpoint for your Kubernetes API server |
| `cluster_id` | The name of the EKS cluster. Works for both existing and new clusters |
| `cluster_name` | The name of the EKS cluster |
| `oidc_provider_arn` | The ARN of the OIDC Provider if `enable_irsa = true` |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.43.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_eks"></a> [eks](#module\_eks) | terraform-aws-modules/eks/aws | 21.19.0 |
| <a name="module_karpenter"></a> [karpenter](#module\_karpenter) | terraform-aws-modules/eks/aws//modules/karpenter | 21.19.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ssm_parameter.cluster_name](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.oidc_provider_arn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_allowed_cidrs"></a> [api\_allowed\_cidrs](#input\_api\_allowed\_cidrs) | List of CIDR blocks that can access the Amazon EKS public API server endpoint | `list(string)` | `[]` | no |
| <a name="input_cluster_addons"></a> [cluster\_addons](#input\_cluster\_addons) | Map of cluster addons to enable | `any` | `{}` | no |
| <a name="input_cluster_endpoint_public_access"></a> [cluster\_endpoint\_public\_access](#input\_cluster\_endpoint\_public\_access) | Indicates whether or not the Amazon EKS public API server endpoint is enabled | `bool` | `true` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster | `string` | n/a | yes |
| <a name="input_desired_size"></a> [desired\_size](#input\_desired\_size) | Desired number of nodes | `number` | `1` | no |
| <a name="input_enable_karpenter"></a> [enable\_karpenter](#input\_enable\_karpenter) | Whether to provision Karpenter AWS prerequisites (IAM roles, SQS queue, EventBridge rules) | `bool` | `true` | no |
| <a name="input_env"></a> [env](#input\_env) | Target environment for naming and discovery contract (e.g. dev, prod) | `string` | `""` | no |
| <a name="input_instance_types"></a> [instance\_types](#input\_instance\_types) | List of instance types for the node group | `list(string)` | <pre>[<br/>  "t4g.small",<br/>  "t4g.medium"<br/>]</pre> | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version to use | `string` | `"1.30"` | no |
| <a name="input_max_size"></a> [max\_size](#input\_max\_size) | Maximum number of nodes | `number` | `3` | no |
| <a name="input_min_size"></a> [min\_size](#input\_min\_size) | Minimum number of nodes | `number` | `1` | no |
| <a name="input_node_security_group_tags"></a> [node\_security\_group\_tags](#input\_node\_security\_group\_tags) | Additional tags for the node security group | `map(string)` | `{}` | no |
| <a name="input_publish_ssm_parameters"></a> [publish\_ssm\_parameters](#input\_publish\_ssm\_parameters) | Whether to publish discovery contract parameters to SSM Parameter Store | `bool` | `false` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for naming and discovery contract (e.g. eu-central-1) | `string` | `""` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | A list of subnet IDs where the EKS nodes will be deployed | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the cluster will be deployed | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | The Amazon Resource Name (ARN) of the cluster |
| <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data) | Base64 encoded certificate data required to communicate with the cluster |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | Endpoint for your Kubernetes API server |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The name of the EKS cluster. Works for both existing and new clusters |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | The name of the EKS cluster |
| <a name="output_karpenter_node_iam_role_arn"></a> [karpenter\_node\_iam\_role\_arn](#output\_karpenter\_node\_iam\_role\_arn) | The ARN of the IAM role for Karpenter nodes |
| <a name="output_karpenter_node_iam_role_name"></a> [karpenter\_node\_iam\_role\_name](#output\_karpenter\_node\_iam\_role\_name) | The name of the IAM role for Karpenter nodes |
| <a name="output_karpenter_queue_arn"></a> [karpenter\_queue\_arn](#output\_karpenter\_queue\_arn) | The ARN of the SQS interruption queue for Karpenter |
| <a name="output_karpenter_queue_name"></a> [karpenter\_queue\_name](#output\_karpenter\_queue\_name) | The name of the SQS interruption queue for Karpenter |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | The ARN of the OIDC Provider if `enable_irsa = true` |
| <a name="output_ssm_cluster_name_parameter"></a> [ssm\_cluster\_name\_parameter](#output\_ssm\_cluster\_name\_parameter) | SSM Parameter Store name for EKS cluster name |
| <a name="output_ssm_oidc_provider_arn_parameter"></a> [ssm\_oidc\_provider\_arn\_parameter](#output\_ssm\_oidc\_provider\_arn\_parameter) | SSM Parameter Store name for EKS OIDC provider ARN |
<!-- END_TF_DOCS -->