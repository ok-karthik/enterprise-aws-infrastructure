# network/tgw-peering

**Status:** 📝 Plan-only (wired into `foundation-live-repo`; not applied to AWS)

Cross-region Transit Gateway peering (PLAN 5.2), applied in **network-hub**, once per region. One region is the **requester** (creates the peering attachment), the other is the **accepter** (accepts it). It is its own module so the two regional transit gateways stay independent: if peering lived inside `network/transit-gateway`, each region's transit gateway would need the other's output, which is a Terragrunt dependency cycle.

## Order of applies

```
eu-central-1/transit-gateway ─┐
                              ├─► eu-central-1/tgw-peering (requester) ─► eu-west-1/tgw-peering (accepter)
eu-west-1/transit-gateway ────┘                                            (also depends on eu-west-1/transit-gateway)
```

- `role = "requester"` (primary region): needs `transit_gateway_id`, `peer_transit_gateway_id` and `peer_region`. `peer_account_id` defaults to the caller's account.
- `role = "accepter"` (secondary region): needs `peering_attachment_id`, the requester's `peering_attachment_id` output, passed in through a Terragrunt `dependency` block.

## Not included yet

- **Static routes over the peering attachment are not included.** Peering attachments do not propagate routes, so traffic only flows once routes pointing at the attachment are added to the transit gateway route tables. The old peering code inside `network/transit-gateway` had none either.

## Not verified offline

- Cross-region peering, in both directions, against real AWS.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.67.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ec2_transit_gateway_peering_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_peering_attachment) | resource |
| [aws_ec2_transit_gateway_peering_attachment_accepter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_peering_attachment_accepter) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_peer_account_id"></a> [peer\_account\_id](#input\_peer\_account\_id) | Requester only: account that owns the peer transit gateway. Defaults to the caller's account (same-account peering, which is what a single network-hub account needs). | `string` | `null` | no |
| <a name="input_peer_region"></a> [peer\_region](#input\_peer\_region) | Requester only: region of the peer transit gateway. | `string` | `null` | no |
| <a name="input_peer_transit_gateway_id"></a> [peer\_transit\_gateway\_id](#input\_peer\_transit\_gateway\_id) | Requester only: ID of the other region's transit gateway (the peering attachment goes TO it). | `string` | `null` | no |
| <a name="input_peering_attachment_id"></a> [peering\_attachment\_id](#input\_peering\_attachment\_id) | Accepter only: ID of the peering attachment to accept (the requester's peering\_attachment\_id output, passed in through a Terragrunt dependency). | `string` | `null` | no |
| <a name="input_role"></a> [role](#input\_role) | Which side of the peering this application is: "requester" creates the peering attachment, "accepter" accepts it. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_transit_gateway_id"></a> [transit\_gateway\_id](#input\_transit\_gateway\_id) | Requester only: ID of this region's transit gateway (the peering attachment is created FROM it). | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_peering_attachment_id"></a> [peering\_attachment\_id](#output\_peering\_attachment\_id) | ID of the peering attachment: the one this requester created, or the one this accepter accepted. The accepter's Terragrunt unit reads the requester's value. |
<!-- END_TF_DOCS -->
