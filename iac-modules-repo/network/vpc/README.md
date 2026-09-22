# network/vpc

Reusable VPC module wrapping `terraform-aws-modules/vpc/aws`. Ships hardened by default: a deny-all default network ACL, a black-hole default security group (no ingress/egress), and VPC Flow Logs shipped to CloudWatch — so a caller cannot accidentally get an open-by-default network.

## Inputs

| Name | Description | Type | Default |
| :--- | :--- | :--- | :--- |
| `name` | Name to be used on all resources as prefix | `string` | n/a |
| `cidr` | The CIDR block for the VPC | `string` | n/a |
| `azs` | A list of availability zones names or ids in the region | `list(string)` | n/a |
| `private_subnets` | A list of private subnets inside the VPC | `list(string)` | n/a |
| `public_subnets` | A list of public subnets inside the VPC | `list(string)` | n/a |
| `enable_nat_gateway` | Should be true if you want to provision NAT Gateways for each of your private networks | `bool` | `true` |
| `single_nat_gateway` | Should be true if you want to provision a single shared NAT Gateway across all of your private networks | `bool` | `true` |
| `cluster_name` | Name of the EKS cluster to tag subnets for | `string` | `""` |
| `tags` | A map of tags to add to all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
| :--- | :--- |
| `vpc_id` | The ID of the VPC |
| `private_subnets` | List of IDs of private subnets |
| `public_subnets` | List of IDs of public subnets |
| `nat_public_ips` | List of public Elastic IP addresses created for HTTP Load Balancing |
| `vpc_cidr_block` | The CIDR block of the VPC |


## IPAM (PLAN 5.1)

Exactly one of `cidr`, or both `ipv4_ipam_pool_id` and `ipv4_netmask_length`, must be set. In IPAM mode, the default network ACL's "allow from inside the VPC" rule cannot use the real VPC CIDR (it is only known after AWS allocates it at apply), so it widens to `var.default_network_acl_allow_cidr` if you set it, or `10.0.0.0/8` (network/ipam's default `top_level_cidr`) if you don't. Set `default_network_acl_allow_cidr` to the exact allocated range once you know it, to narrow this back down. Security groups, not this NACL, are the primary control either way.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.65.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | 6.6.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ssm_parameter.database_subnets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.vpc_id](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_azs"></a> [azs](#input\_azs) | A list of availability zones names or ids in the region | `list(string)` | n/a | yes |
| <a name="input_cidr"></a> [cidr](#input\_cidr) | The CIDR block for the VPC. Exactly one of cidr or (ipv4\_ipam\_pool\_id + ipv4\_netmask\_length) must be set (PLAN 5.1). | `string` | `""` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster to tag subnets for | `string` | `""` | no |
| <a name="input_database_subnets"></a> [database\_subnets](#input\_database\_subnets) | A list of database subnets inside the VPC | `list(string)` | `[]` | no |
| <a name="input_default_network_acl_allow_cidr"></a> [default\_network\_acl\_allow\_cidr](#input\_default\_network\_acl\_allow\_cidr) | CIDR the default network ACL allows ingress from. Empty means: use var.cidr when it is set, or<br/>"10.0.0.0/8" (the platform's whole IPAM address space, network/ipam's default top\_level\_cidr) when using<br/>IPAM, because the real allocated CIDR is not known until after the first apply. Set this explicitly (the<br/>env pool's own range, once you know it) to narrow it back down for an IPAM-sourced VPC. | `string` | `""` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Should be true if you want to provision NAT Gateways for each of your private networks | `bool` | `true` | no |
| <a name="input_env"></a> [env](#input\_env) | Target environment for naming and discovery contract (e.g. dev, prod) | `string` | `""` | no |
| <a name="input_ipv4_ipam_pool_id"></a> [ipv4\_ipam\_pool\_id](#input\_ipv4\_ipam\_pool\_id) | IPAM pool to request the VPC's CIDR from (network/ipam's env\_pool\_ids output), instead of a literal cidr. Requires ipv4\_netmask\_length too. | `string` | `""` | no |
| <a name="input_ipv4_netmask_length"></a> [ipv4\_netmask\_length](#input\_ipv4\_netmask\_length) | Netmask length to request from ipv4\_ipam\_pool\_id, e.g. 20 for a /20. Requires ipv4\_ipam\_pool\_id too. | `number` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name to be used on all resources as prefix | `string` | n/a | yes |
| <a name="input_private_subnets"></a> [private\_subnets](#input\_private\_subnets) | A list of private subnets inside the VPC | `list(string)` | n/a | yes |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | A list of public subnets inside the VPC | `list(string)` | n/a | yes |
| <a name="input_publish_ssm_parameters"></a> [publish\_ssm\_parameters](#input\_publish\_ssm\_parameters) | Whether to publish discovery contract parameters to SSM Parameter Store | `bool` | `false` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for naming and discovery contract (e.g. eu-central-1) | `string` | `""` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Should be true if you want to provision a single shared NAT Gateway across all of your private networks | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_database_subnet_group_name"></a> [database\_subnet\_group\_name](#output\_database\_subnet\_group\_name) | Name of database subnet group |
| <a name="output_database_subnets"></a> [database\_subnets](#output\_database\_subnets) | List of IDs of database subnets |
| <a name="output_nat_public_ips"></a> [nat\_public\_ips](#output\_nat\_public\_ips) | List of public Elastic IP addresses created for HTTP Load Balancing |
| <a name="output_private_subnets"></a> [private\_subnets](#output\_private\_subnets) | List of IDs of private subnets |
| <a name="output_public_subnets"></a> [public\_subnets](#output\_public\_subnets) | List of IDs of public subnets |
| <a name="output_ssm_database_subnets_parameter"></a> [ssm\_database\_subnets\_parameter](#output\_ssm\_database\_subnets\_parameter) | SSM Parameter Store name for database subnets |
| <a name="output_ssm_vpc_id_parameter"></a> [ssm\_vpc\_id\_parameter](#output\_ssm\_vpc\_id\_parameter) | SSM Parameter Store name for VPC ID |
| <a name="output_vpc_cidr_block"></a> [vpc\_cidr\_block](#output\_vpc\_cidr\_block) | The CIDR block of the VPC |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the VPC |
<!-- END_TF_DOCS -->
