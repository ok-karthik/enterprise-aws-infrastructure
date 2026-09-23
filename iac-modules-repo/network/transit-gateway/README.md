# network/transit-gateway

Transit Gateway (PLAN 5.2), applied in **network-hub**, once per region. Default route table association and propagation are **off**: nothing lands anywhere by accident. Four route tables: `prod`, `nonprod`, `shared`, `inspection`. **Prod and nonprod never route to each other**, because each spoke associates and propagates into exactly one of those two tables (`network/tgw-attachment`'s `route_table_id`), never both.

## Sharing and attaching a spoke

The transit gateway **itself** (not a route table) is shared with the Workloads and Infrastructure OUs through RAM. A workload account attaches with `network/tgw-attachment`, which creates the attachment and associates/propagates it into one route table. The transit gateway does **not** auto-accept (`auto_accept_shared_attachments` defaults to off): `var.accept_vpc_attachments` here discovers pending attachments (a data source, filtered on this transit gateway's id and `state = pendingAcceptance`) and accepts each one — matching PLAN 5.2's "the acceptance side is in network-hub".

**`accept_vpc_attachments` defaults to off**, and stays off through the transit gateway's *first* apply: on that first apply the transit gateway does not exist yet, so a `for_each` built from a data source that reads it back cannot resolve (a real Terraform limitation, confirmed while writing this module's tests, not a documentation guess). Turn it on in a *later* apply, once the transit gateway exists and a spoke has actually requested an attachment.

## Cross-region peering (`var.peering`)

This module is applied once per region; the two applications coordinate through `var.peering.role`:
- `"requester"` (in one region): creates the peering attachment to the other region's transit gateway.
- `"accepter"` (in the other region): accepts it, given `accepter_attachment_id` — the requester's `peering_attachment_id` output, passed in through a Terragrunt `dependency` block.

## Hybrid connectivity (PLAN 5.6)

`enable_site_to_site_vpn` and `enable_direct_connect_gateway_association` are both **off by default: module and docs only, there is no real peer to connect to**. Both attach to the transit gateway directly (not a VPN Gateway), consistent with the hub-and-spoke design.

## Not verified offline

- The RAM-share → attach → discover-and-accept flow, end to end, against real AWS.
- Cross-region peering, in both directions.
- Whatever real on-premises VPN/Direct Connect endpoint eventually exists (there is none yet).

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
| [aws_customer_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/customer_gateway) | resource |
| [aws_dx_gateway_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dx_gateway_association) | resource |
| [aws_ec2_transit_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway) | resource |
| [aws_ec2_transit_gateway_peering_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_peering_attachment) | resource |
| [aws_ec2_transit_gateway_peering_attachment_accepter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_peering_attachment_accepter) | resource |
| [aws_ec2_transit_gateway_route_table.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route_table) | resource |
| [aws_ec2_transit_gateway_vpc_attachment_accepter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment_accepter) | resource |
| [aws_ram_principal_association.infrastructure_ou](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_principal_association) | resource |
| [aws_ram_principal_association.workloads_ou](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_principal_association) | resource |
| [aws_ram_resource_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_association) | resource |
| [aws_ram_resource_share.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_share) | resource |
| [aws_vpn_connection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_ec2_transit_gateway_vpc_attachments.pending](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_transit_gateway_vpc_attachments) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_accept_vpc_attachments"></a> [accept\_vpc\_attachments](#input\_accept\_vpc\_attachments) | Discover and accept pending VPC attachments from spoke accounts (RAM-shared, so only principals in<br/>workloads\_ou\_arn / infrastructure\_ou\_arn could ever create one). The transit gateway itself defaults to<br/>NOT auto-accepting (var.auto\_accept\_shared\_attachments), so this explicit, reviewable accept step in<br/>network-hub is what actually attaches a spoke -- matching PLAN 5.2's "the acceptance side is in<br/>network-hub". Off by default and turned on in a LATER apply, never the transit gateway's first one: on<br/>a first apply the transit gateway does not exist yet, so a for\_each built from a data source that reads<br/>it cannot resolve (a real Terraform limitation, not just a mock artifact). Turn it on once the transit<br/>gateway exists and a spoke has actually requested an attachment. | `bool` | `false` | no |
| <a name="input_amazon_side_asn"></a> [amazon\_side\_asn](#input\_amazon\_side\_asn) | BGP ASN on the Amazon side of the transit gateway (used for VPN/Direct Connect BGP sessions). | `number` | `64512` | no |
| <a name="input_auto_accept_shared_attachments"></a> [auto\_accept\_shared\_attachments](#input\_auto\_accept\_shared\_attachments) | Whether the transit gateway itself auto-accepts a RAM-shared attachment request. Off by default: var.accept\_vpc\_attachments is the explicit, reviewable path instead. | `bool` | `false` | no |
| <a name="input_customer_gateway_bgp_asn"></a> [customer\_gateway\_bgp\_asn](#input\_customer\_gateway\_bgp\_asn) | BGP ASN of the on-premises VPN device. | `number` | `65000` | no |
| <a name="input_customer_gateway_ip"></a> [customer\_gateway\_ip](#input\_customer\_gateway\_ip) | Public IP of the on-premises VPN device. Required when enable\_site\_to\_site\_vpn is true. | `string` | `""` | no |
| <a name="input_direct_connect_gateway_allowed_prefixes"></a> [direct\_connect\_gateway\_allowed\_prefixes](#input\_direct\_connect\_gateway\_allowed\_prefixes) | CIDR blocks the Direct Connect gateway may advertise to the transit gateway. | `list(string)` | `[]` | no |
| <a name="input_direct_connect_gateway_id"></a> [direct\_connect\_gateway\_id](#input\_direct\_connect\_gateway\_id) | ID of an existing Direct Connect gateway. Required when enable\_direct\_connect\_gateway\_association is true. | `string` | `""` | no |
| <a name="input_enable_direct_connect_gateway_association"></a> [enable\_direct\_connect\_gateway\_association](#input\_enable\_direct\_connect\_gateway\_association) | Associate a Direct Connect gateway with the transit gateway. Off by default: needs a real direct\_connect\_gateway\_id. | `bool` | `false` | no |
| <a name="input_enable_site_to_site_vpn"></a> [enable\_site\_to\_site\_vpn](#input\_enable\_site\_to\_site\_vpn) | Create a Customer Gateway and a Site-to-Site VPN connection attached to the transit gateway. Off by default: needs a real customer\_gateway\_ip. | `bool` | `false` | no |
| <a name="input_infrastructure_ou_arn"></a> [infrastructure\_ou\_arn](#input\_infrastructure\_ou\_arn) | ARN of the Infrastructure OU. Shared the same way as workloads\_ou\_arn. | `string` | n/a | yes |
| <a name="input_peering"></a> [peering](#input\_peering) | Cross-region peering to another region's transit gateway (PLAN 5.2, primary\_region <-> secondary\_region).<br/>role = "none" (default): no peering attachment from this region.<br/>role = "requester": creates the peering attachment FROM this region's transit gateway TO<br/>  peer\_transit\_gateway\_id in peer\_region (peer\_account\_id defaults to this account, i.e. same-account<br/>  peering, which is what a single network-hub account needs).<br/>role = "accepter": accepts a peering attachment created by the OTHER region's requester<br/>  (accepter\_attachment\_id -- that region's module output peering\_attachment\_id, passed in through a<br/>  Terragrunt dependency). | <pre>object({<br/>    role                    = optional(string, "none")<br/>    peer_transit_gateway_id = optional(string)<br/>    peer_region             = optional(string)<br/>    peer_account_id         = optional(string)<br/>    accepter_attachment_id  = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_workloads_ou_arn"></a> [workloads\_ou\_arn](#input\_workloads\_ou\_arn) | ARN of the Workloads OU. The transit gateway itself (not its route tables) is shared with this OU and infrastructure\_ou\_arn through RAM, so spoke accounts can attach to it. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_accepted_vpc_attachment_ids"></a> [accepted\_vpc\_attachment\_ids](#output\_accepted\_vpc\_attachment\_ids) | IDs of the spoke VPC attachments this leaf discovered and accepted |
| <a name="output_peering_attachment_id"></a> [peering\_attachment\_id](#output\_peering\_attachment\_id) | ID of the peering attachment this region created as requester, or null (used by the other region's accepter, via a Terragrunt dependency) |
| <a name="output_resource_share_arn"></a> [resource\_share\_arn](#output\_resource\_share\_arn) | ARN of the RAM share the transit gateway itself is shared through |
| <a name="output_route_table_ids"></a> [route\_table\_ids](#output\_route\_table\_ids) | Route table name (prod, nonprod, shared, inspection) => its ID |
| <a name="output_transit_gateway_arn"></a> [transit\_gateway\_arn](#output\_transit\_gateway\_arn) | ARN of the transit gateway |
| <a name="output_transit_gateway_id"></a> [transit\_gateway\_id](#output\_transit\_gateway\_id) | ID of the transit gateway |
<!-- END_TF_DOCS -->
