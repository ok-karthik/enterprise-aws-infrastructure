# identity/human-access

Human access to an **EKS cluster**: access entries (with Kubernetes groups) and the cluster view policy per team. The IAM Identity Center permission sets that used to live here (`PlatformAdmin`, `Developer`, `AuditorReadOnly`, ...) moved to [`identity/identity-center`](../identity-center/README.md), which owns the whole permission-set catalog and the assignments.

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

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster to grant access entries for | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_team_access"></a> [team\_access](#input\_team\_access) | Map of (team, tier) access configurations with principal ARN and kubernetes groups | <pre>map(object({<br/>    principal_arn = string<br/>    k8s_groups    = list(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_entry_arns"></a> [access\_entry\_arns](#output\_access\_entry\_arns) | Map of EKS Access Entry ARNs created for teams |
<!-- END_TF_DOCS -->
