# Cross-region transit gateway peering (PLAN 5.2), applied in network-hub, once per region. One region is the
# requester (it creates the peering attachment), the other is the accepter (it accepts that attachment).
# This is its own unit, not part of network/transit-gateway, so the two regional transit gateways do not have to
# depend on each other (that was a Terragrunt dependency cycle).

data "aws_caller_identity" "current" {
  count = var.role == "requester" ? 1 : 0
}

resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  count = var.role == "requester" ? 1 : 0

  transit_gateway_id      = var.transit_gateway_id
  peer_transit_gateway_id = var.peer_transit_gateway_id
  peer_region             = var.peer_region
  peer_account_id         = coalesce(var.peer_account_id, data.aws_caller_identity.current[0].account_id)

  tags = var.tags
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  count = var.role == "accepter" ? 1 : 0

  transit_gateway_attachment_id = var.peering_attachment_id

  tags = var.tags
}
