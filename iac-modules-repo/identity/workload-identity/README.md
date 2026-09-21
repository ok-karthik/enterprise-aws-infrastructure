# identity/workload-identity

Workload identity module providing EKS Pod Identity associations as the primary mechanism, with IRSA (IAM Roles for Service Accounts) as the documented fallback for Fargate and external workloads.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.65.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.4.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_pod_identity_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_openid_connect_provider.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.irsa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.irsa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [tls_certificate.cluster_oidc](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster for Pod Identity associations | `string` | n/a | yes |
| <a name="input_irsa_roles"></a> [irsa\_roles](#input\_irsa\_roles) | Map of (namespace, service account) pairs needing the IRSA fallback instead of Pod Identity | <pre>map(object({<br/>    namespace            = string<br/>    service_account_name = string<br/>    policy_arns          = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_oidc_issuer_url"></a> [oidc\_issuer\_url](#input\_oidc\_issuer\_url) | EKS cluster OIDC issuer URL. Required only if using the IRSA fallback path | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_workload_identities"></a> [workload\_identities](#input\_workload\_identities) | Map of (namespace, service account) pairs to IAM role ARNs using EKS Pod Identity | <pre>map(object({<br/>    namespace            = string<br/>    service_account_name = string<br/>    role_arn             = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_associations"></a> [associations](#output\_associations) | Map of EKS Pod Identity association IDs |
| <a name="output_irsa_role_arns"></a> [irsa\_role\_arns](#output\_irsa\_role\_arns) | Map of IAM role ARNs created for the IRSA fallback path |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | The ARN of the IAM OIDC provider created for IRSA |
<!-- END_TF_DOCS -->
