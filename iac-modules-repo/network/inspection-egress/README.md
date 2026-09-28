# network/inspection-egress

The central egress/inspection VPC (PLAN 5.3), applied in **network-hub**, per region: NAT gateways (one per AZ) behind AWS Network Firewall. Spoke VPCs (`network/vpc` with `egress_mode = "central"`, attached with `network/tgw-attachment`'s `egress_route_cidr`) send `0.0.0.0/0` here instead of using their own NAT gateways.

## Topology

Three subnet tiers per AZ:

| Tier | Holds | Routes |
|---|---|---|
| `tgw` | This VPC's own transit gateway attachment (`appliance_mode_support = enable`, so a flow keeps using the same firewall endpoint) | `0.0.0.0/0` → the Network Firewall endpoint in that AZ |
| `firewall` | The Network Firewall's VPC endpoint | `0.0.0.0/0` → that AZ's NAT gateway |
| `public` | The NAT gateway and the internet gateway route | `0.0.0.0/0` → internet gateway; this VPC's own CIDR → the firewall endpoint (so return traffic is inspected too) |

## The firewall policy: an allow-list, not a deny-list

`var.domain_allow_list` builds one stateful rule group (`generated_rules_type = "ALLOWLIST"`, matching `TLS_SNI` and `HTTP_HOST`). The policy uses `STRICT_ORDER` with `stateful_default_actions = ["aws:drop_established"]`: **anything not in the allow-list is dropped**, once the connection is established. `var.additional_suricata_rules` (raw Suricata, optional) adds a second rule group at a lower priority.

## Logging

Alert and flow logs (the firewall's own) go to `var.log_archive_bucket_name` (`security/log-archive`'s `bucket_names["vpc_flow_logs"]` output — that log type's bucket policy already trusts `delivery.logs.amazonaws.com`, the same central delivery service Network Firewall uses). The VPC's own flow logs (all traffic, not just what the firewall inspected) go to the same bucket, a different prefix.

## Cost

See `FINOPS.md` for the cost comparison against `egress_mode = "local-nat"`. Roughly: one Network Firewall endpoint per AZ (~$395/month per endpoint, `us-east-1` pricing, at the time this was written — check current pricing before applying) plus data processing, versus a NAT gateway per spoke VPC (~$35/month plus data). Centralizing is worth it once there are enough spoke VPCs that shared NAT + firewall costs less than every VPC's own NAT, and it is the only way to get one enforced domain allow-list for every spoke.

## Not verified offline

- The exact shape of `aws_networkfirewall_firewall.firewall_status[0].sync_states[*].attachment[0].endpoint_id` (used to route from the tgw/public subnets to the firewall) was checked against the provider's own schema (not guessed), but never against a real `apply` — confirm it once this is deployed for real.
- Whether the log-archive `vpc_flow_logs` bucket policy really accepts Network Firewall's S3 log delivery (both use `delivery.logs.amazonaws.com`, but this was not tested against a real delivery).

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
| [aws_ec2_transit_gateway_route_table_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route_table_association) | resource |
| [aws_ec2_transit_gateway_route_table_propagation.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route_table_propagation) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_kms_alias.firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_networkfirewall_firewall.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_firewall) | resource |
| [aws_networkfirewall_firewall_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_firewall_policy) | resource |
| [aws_networkfirewall_logging_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_logging_configuration) | resource |
| [aws_networkfirewall_rule_group.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_rule_group) | resource |
| [aws_networkfirewall_rule_group.domain_allow_list](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_rule_group) | resource |
| [aws_route.firewall_to_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_to_firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_to_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.tgw_to_firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_suricata_rules"></a> [additional\_suricata\_rules](#input\_additional\_suricata\_rules) | Extra stateful rules in raw Suricata format, appended after the domain allow-list rule group. Empty by default. | `string` | `""` | no |
| <a name="input_azs"></a> [azs](#input\_azs) | Availability zones to spread NAT gateways and firewall endpoints across (one of each per AZ). | `list(string)` | n/a | yes |
| <a name="input_domain_allow_list"></a> [domain\_allow\_list](#input\_domain\_allow\_list) | Domains (TLS SNI / HTTP Host) the stateful firewall rule group allows. Traffic to any other domain is dropped -- this is an allow-list, not a deny-list. | `list(string)` | n/a | yes |
| <a name="input_inspection_route_table_id"></a> [inspection\_route\_table\_id](#input\_inspection\_route\_table\_id) | The transit gateway's "inspection" route table id, this attachment associates/propagates into. | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | S3 bucket in log-archive to send firewall alert and flow logs to: security/log-archive's bucket\_names["vpc\_flow\_logs"] output (both log types share it; log-archive has no dedicated Network Firewall bucket type). | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for every resource. | `string` | `"inspection-egress"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_transit_gateway_id"></a> [transit\_gateway\_id](#input\_transit\_gateway\_id) | ID of the transit gateway to attach to (network/transit-gateway's output), so spoke traffic can reach this VPC. | `string` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR for the inspection/egress VPC. Sized for three /AZ subnet tiers (tgw, firewall, public). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_firewall_arn"></a> [firewall\_arn](#output\_firewall\_arn) | ARN of the Network Firewall |
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | AZ => NAT gateway ID |
| <a name="output_tgw_attachment_id"></a> [tgw\_attachment\_id](#output\_tgw\_attachment\_id) | ID of this VPC's own transit gateway attachment |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the inspection/egress VPC |
<!-- END_TF_DOCS -->
