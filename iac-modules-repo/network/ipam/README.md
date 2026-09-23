# network/ipam

The org-wide IPAM (PLAN 5.1), applied in **network-hub**: a top-level pool, one regional pool per region (carved from the top-level pool), and `prod`/`nonprod` env pools under each regional pool.

## Sharing

The **env pools only** (not the regional or top-level pools) are shared with the **Workloads OU** through RAM (`aws_ram_resource_share` + `aws_ram_principal_association`). Sharing the env pools, not the wider ones, means a workload account can only ever request a CIDR from its own env's slice, never from another environment's or region's space.

RAM sharing with an entire OU needs **organization sharing** turned on for the whole AWS Organization (`aws_ram_sharing_with_organization`) — a one-time, organization-wide setting, not scoped to one resource share, so it is not created by this module. Turn it on once (owner step) before the first apply here.

## Using a pool from `network/vpc`

`network/vpc` takes `ipv4_ipam_pool_id` + `ipv4_netmask_length` as an alternative to a literal `cidr` (PLAN 5.1). Pass this module's `env_pool_ids["<region>/<prod|nonprod>"]` output as `ipv4_ipam_pool_id`.

## Not verified offline

- That `aws_ram_sharing_with_organization` really is a one-time, org-wide toggle at the time this was written — check the current AWS documentation.
- The actual CIDR sizes (`top_level_cidr`, each region's `regional_pools[...].cidr`, `prod_env_netmask_length` / `nonprod_env_netmask_length`): sized for a small platform by default: adjust before a real, larger rollout.

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
| [aws_ram_principal_association.workloads_ou](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_principal_association) | resource |
| [aws_ram_resource_association.pools](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_association) | resource |
| [aws_ram_resource_share.pools](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_share) | resource |
| [aws_vpc_ipam.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipam) | resource |
| [aws_vpc_ipam_pool.env](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipam_pool) | resource |
| [aws_vpc_ipam_pool.regional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipam_pool) | resource |
| [aws_vpc_ipam_pool.top_level](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipam_pool) | resource |
| [aws_vpc_ipam_pool_cidr.env](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipam_pool_cidr) | resource |
| [aws_vpc_ipam_pool_cidr.regional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipam_pool_cidr) | resource |
| [aws_vpc_ipam_pool_cidr.top_level](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipam_pool_cidr) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_nonprod_env_netmask_length"></a> [nonprod\_env\_netmask\_length](#input\_nonprod\_env\_netmask\_length) | Netmask length of each region's nonprod env pool. | `number` | `10` | no |
| <a name="input_operating_regions"></a> [operating\_regions](#input\_operating\_regions) | Regions IPAM operates in. Must include every region a regional pool is created for. | `list(string)` | <pre>[<br/>  "eu-central-1",<br/>  "eu-west-1"<br/>]</pre> | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | ID of the AWS Organization (o-xxxxxxxxxx). The pools are shared with the Workloads OU via RAM, which needs organization sharing turned on (aws\_ram\_sharing\_with\_organization, applied once per organization elsewhere -- see the module README). | `string` | n/a | yes |
| <a name="input_prod_env_netmask_length"></a> [prod\_env\_netmask\_length](#input\_prod\_env\_netmask\_length) | Netmask length of each region's prod env pool (a /netmask carved from that region's pool). | `number` | `10` | no |
| <a name="input_regional_pools"></a> [regional\_pools](#input\_regional\_pools) | One entry per region: the locale (region) and the CIDR carved out of top\_level\_cidr for it. Each regional<br/>pool gets two child pools, "prod" and "nonprod", splitting the region's space by<br/>prod\_env\_netmask\_length / nonprod\_env\_netmask\_length. | <pre>map(object({<br/>    locale = string<br/>    cidr   = string<br/>  }))</pre> | <pre>{<br/>  "eu-central-1": {<br/>    "cidr": "10.0.0.0/9",<br/>    "locale": "eu-central-1"<br/>  },<br/>  "eu-west-1": {<br/>    "cidr": "10.128.0.0/9",<br/>    "locale": "eu-west-1"<br/>  }<br/>}</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_top_level_cidr"></a> [top\_level\_cidr](#input\_top\_level\_cidr) | The org-wide IPv4 CIDR the top-level pool is carved from (RFC 1918 space, sized for every account and region this platform will ever use). | `string` | `"10.0.0.0/8"` | no |
| <a name="input_workloads_ou_arn"></a> [workloads\_ou\_arn](#input\_workloads\_ou\_arn) | ARN of the Workloads OU (governance/organization's organizational\_unit\_ids["Workloads"], turned into an OU ARN). The regional pools are shared with this OU. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_env_pool_ids"></a> [env\_pool\_ids](#output\_env\_pool\_ids) | "<region>/<env>" => env pool ID (env is prod or nonprod), for network/vpc's ipv4\_ipam\_pool\_id input |
| <a name="output_ipam_id"></a> [ipam\_id](#output\_ipam\_id) | ID of the org-wide IPAM |
| <a name="output_regional_pool_ids"></a> [regional\_pool\_ids](#output\_regional\_pool\_ids) | Region => regional pool ID |
| <a name="output_resource_share_arn"></a> [resource\_share\_arn](#output\_resource\_share\_arn) | ARN of the RAM share the regional pools are shared through |
| <a name="output_top_level_pool_id"></a> [top\_level\_pool\_id](#output\_top\_level\_pool\_id) | ID of the top-level pool |
<!-- END_TF_DOCS -->
