# network/tgw-attachment

Spoke-side transit gateway attachment (PLAN 5.2), applied in a **workload account**. Requests an attachment to the RAM-shared transit gateway in network-hub (`var.transit_gateway_id`, `network/transit-gateway`'s output), and associates/propagates it into exactly **one** route table (`var.route_table_id` — `prod` or `nonprod`, never both: they cannot route to each other).

The attachment stays `pendingAcceptance` until `network/transit-gateway`'s `accept_vpc_attachments` runs in network-hub (that module's README explains why that only happens after the transit gateway's first apply, not during it).

## Central egress (PLAN 5.3, optional)

`var.egress_route_cidr` (typically `"0.0.0.0/0"`) adds a route in `var.private_route_table_ids` pointing at the transit gateway — this VPC's own default route, for `network/vpc`'s `egress_mode = "central"` (the central egress VPC, `network/inspection-egress`, does the actual NAT/firewalling). Leave it empty for `egress_mode = "local-nat"` (the VPC keeps its own NAT gateways).

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
| [aws_route.egress_via_tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_appliance_mode_support"></a> [appliance\_mode\_support](#input\_appliance\_mode\_support) | Enable appliance mode (keeps a flow pinned to one AZ's route, needed for a stateful appliance like the inspection VPC's firewall, PLAN 5.3). Off for an ordinary spoke VPC. | `bool` | `false` | no |
| <a name="input_egress_route_cidr"></a> [egress\_route\_cidr](#input\_egress\_route\_cidr) | Destination CIDR to add to THIS VPC's own route tables pointing at the transit gateway, e.g. "0.0.0.0/0" for central egress (network/vpc's egress\_mode = "central", PLAN 5.3). Empty adds no route here (the caller manages its own routes, or uses egress\_mode = "local-nat"). | `string` | `""` | no |
| <a name="input_private_route_table_ids"></a> [private\_route\_table\_ids](#input\_private\_route\_table\_ids) | This VPC's own private route table IDs, to add egress\_route\_cidr to. Required when egress\_route\_cidr is set. | `list(string)` | `[]` | no |
| <a name="input_route_table_id"></a> [route\_table\_id](#input\_route\_table\_id) | Transit gateway route table to associate and propagate this attachment into (network/transit-gateway's route\_table\_ids["prod"] or ["nonprod"], never both -- prod and nonprod cannot route to each other, PLAN 5.2). | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs the attachment uses (one per AZ; usually the private subnets). At least one is required, and one per AZ is recommended for resilience. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_transit_gateway_id"></a> [transit\_gateway\_id](#input\_transit\_gateway\_id) | ID of the transit gateway to attach to (network/transit-gateway's output, from the network-hub account, RAM-shared with this account's OU). | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC to attach. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_attachment_id"></a> [attachment\_id](#output\_attachment\_id) | ID of the VPC attachment (pending acceptance in network-hub until its accept step runs) |
<!-- END_TF_DOCS -->
