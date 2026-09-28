# network/dns

DNS (PLAN 5.5), applied in **network-hub**, per region: Route 53 Resolver inbound/outbound endpoints, forwarding rules for on-premises domains, resolver query logging, and public hosted zones with per-workload-account delegated subdomains.

## Resolver

- **Inbound** endpoint: lets on-premises resolvers query the platform's private DNS (needs `var.on_prem_cidr_blocks`, the hybrid connectivity in `network/transit-gateway`, PLAN 5.6).
- **Outbound** endpoint + **forwarding rules** (`var.forwarding_rules`, domain → on-prem DNS server IPs): forwards platform queries for on-premises domains outward. Each rule is RAM-shared with the Workloads OU, the same pattern as `network/ipam` and `network/transit-gateway`.
- **Query log config**: shared the same way, associated with this module's own VPC. Destination is `var.query_log_destination_arn` — an S3 bucket (`security/log-archive`'s `vpc_flow_logs` bucket, the same one `network/inspection-egress` uses) or a CloudWatch Logs group.

## Public hosted zones and delegation

`var.root_domain` (empty by default: creates nothing) is the platform's root domain, hosted here. `var.delegated_subdomains` (workload account name → subdomain label) creates one child public hosted zone per entry, plus an NS delegation record in the root zone. The workload account is expected to use that child zone (a `data "aws_route53_zone"` lookup by id, or its own zone matching those name servers) for its own records — not built by this module.

## Not built (Checkov CKV2_AWS_38 / CKV2_AWS_39, both inline-skipped with a reason)

**DNSSEC signing** and **public-zone query logging** both need a resource **in `us-east-1` specifically** (a KMS key for DNSSEC signing, a CloudWatch Logs group for query logging) — an AWS requirement unrelated to this module's own region. This module is pure (no `provider` blocks, per repo convention), so it cannot create either; both need a `us-east-1`-aliased provider at the **live layer**, which is a follow-up, not built here.

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
| [aws_cloudwatch_log_group.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_ram_principal_association.workloads_ou](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_principal_association) | resource |
| [aws_ram_resource_association.query_log_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_association) | resource |
| [aws_ram_resource_association.rules](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_association) | resource |
| [aws_ram_resource_share.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_share) | resource |
| [aws_route53_record.delegation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_resolver_endpoint.inbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.outbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_query_log_config.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_query_log_config) | resource |
| [aws_route53_resolver_query_log_config_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_query_log_config_association) | resource |
| [aws_route53_resolver_rule.forwarding](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule) | resource |
| [aws_route53_zone.delegated](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_route53_zone.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_security_group.inbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.outbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_security_group_egress_rule.inbound_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.outbound_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.inbound_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.inbound_udp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_azs"></a> [azs](#input\_azs) | Availability zones for the resolver endpoint subnets (at least two, AWS's own minimum). | `list(string)` | n/a | yes |
| <a name="input_delegated_subdomains"></a> [delegated\_subdomains](#input\_delegated\_subdomains) | workload account name => subdomain label (e.g. { "workloads-dev" = "dev" } for dev.<root\_domain>). Each<br/>gets its OWN public hosted zone here, plus an NS delegation record in the root zone. The workload account<br/>is expected to use that zone's name servers for its own subdomain records (not built here: the workload<br/>account needs its own aws\_route53\_zone matching, or a data source reading this zone's id, depending on<br/>who is meant to own records in it -- see the module README). Needs root\_domain to be set. | `map(string)` | `{}` | no |
| <a name="input_forwarding_rules"></a> [forwarding\_rules](#input\_forwarding\_rules) | domain\_name => list of on-premises DNS server IPs to forward that domain to (a FORWARD resolver rule per entry, shared with workloads\_ou\_arn through RAM). | `map(list(string))` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for every resource. | `string` | `"dns"` | no |
| <a name="input_on_prem_cidr_blocks"></a> [on\_prem\_cidr\_blocks](#input\_on\_prem\_cidr\_blocks) | CIDR blocks allowed to query the inbound resolver endpoint (on-premises networks, reached over the hybrid connectivity in network/transit-gateway, PLAN 5.6). | `list(string)` | `[]` | no |
| <a name="input_query_log_destination_arn"></a> [query\_log\_destination\_arn](#input\_query\_log\_destination\_arn) | Where resolver query logs go: an S3 bucket ARN (security/log-archive's vpc\_flow\_logs bucket, the same one network/inspection-egress uses) or a CloudWatch Logs group ARN. | `string` | n/a | yes |
| <a name="input_root_domain"></a> [root\_domain](#input\_root\_domain) | The platform's public root domain, hosted in network-hub. Empty (the default) creates no public zone. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR for this module's own small VPC (the resolver endpoints need ENIs somewhere). | `string` | n/a | yes |
| <a name="input_workloads_ou_arn"></a> [workloads\_ou\_arn](#input\_workloads\_ou\_arn) | ARN of the Workloads OU. Forwarding rules and the query log config are shared with this OU through RAM. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_delegated_zone_ids"></a> [delegated\_zone\_ids](#output\_delegated\_zone\_ids) | Workload account name => its delegated subdomain's public hosted zone ID |
| <a name="output_inbound_endpoint_id"></a> [inbound\_endpoint\_id](#output\_inbound\_endpoint\_id) | ID of the inbound resolver endpoint (on-prem queries the platform through this) |
| <a name="output_outbound_endpoint_id"></a> [outbound\_endpoint\_id](#output\_outbound\_endpoint\_id) | ID of the outbound resolver endpoint (the platform forwards on-prem-domain queries through this) |
| <a name="output_resolver_rule_ids"></a> [resolver\_rule\_ids](#output\_resolver\_rule\_ids) | domain\_name => resolver rule ID |
| <a name="output_resolver_share_arn"></a> [resolver\_share\_arn](#output\_resolver\_share\_arn) | ARN of the RAM share the forwarding rules and query log config are shared through |
| <a name="output_root_zone_id"></a> [root\_zone\_id](#output\_root\_zone\_id) | ID of the public root zone, or null when root\_domain is empty |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of this module's own VPC |
<!-- END_TF_DOCS -->
