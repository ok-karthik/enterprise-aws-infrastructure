# Spoke-side transit gateway attachment (PLAN 5.2), applied in a WORKLOAD account. Requests an attachment to
# the RAM-shared transit gateway in network-hub, associates and propagates it into one route table (prod or
# nonprod, never both), and optionally adds a default route in this VPC's own tables pointing at the
# transit gateway (central egress, PLAN 5.3). The acceptance side is network-hub
# (network/transit-gateway's var.accept_vpc_attachments): this attachment stays "pendingAcceptance" until
# that runs.

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids

  appliance_mode_support = var.appliance_mode_support ? "enable" : "disable"

  # Managed explicitly below (network/transit-gateway's TGW has both defaults off), not by the attachment's
  # own defaults, so a spoke only ever lands in the one route table it was told to use.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = var.tags
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.route_table_id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.route_table_id
}

resource "aws_route" "egress_via_tgw" {
  for_each = var.egress_route_cidr != "" ? toset(var.private_route_table_ids) : []

  route_table_id         = each.value
  destination_cidr_block = var.egress_route_cidr
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}
