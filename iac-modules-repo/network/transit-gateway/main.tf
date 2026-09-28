# Transit Gateway (PLAN 5.2), applied in network-hub, per region: default association and propagation OFF
# (route tables are managed explicitly), four route tables (prod, nonprod, shared, inspection), shared with
# the Workloads and Infrastructure OUs through RAM. Cross-region peering and hybrid connectivity (PLAN 5.6)
# are optional. Spoke VPCs attach with network/tgw-attachment, applied in the workload account; the
# acceptance side is here (var.accept_vpc_attachments).

resource "aws_ec2_transit_gateway" "this" {
  description                     = "Platform transit gateway (PLAN 5.2)"
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = var.auto_accept_shared_attachments ? "enable" : "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Route tables: prod and nonprod never propagate to each other (each spoke associates and propagates only
# into its own table; "shared" is for shared-services attachments both envs may reach; "inspection" is the
# egress VPC's table, PLAN 5.3).
# ------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = toset(["prod", "nonprod", "shared", "inspection"])

  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, { Name = "tgw-${each.key}" })
}

# ------------------------------------------------------------------------------
# RAM: share the transit gateway ITSELF (not the route tables -- a spoke account needs to see the TGW to
# attach to it; route table associations happen from this side, after network/tgw-attachment creates the
# attachment and it is accepted below).
# ------------------------------------------------------------------------------
resource "aws_ram_resource_share" "this" {
  name                      = "transit-gateway"
  allow_external_principals = false

  tags = var.tags
}

resource "aws_ram_resource_association" "this" {
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_principal_association" "workloads_ou" {
  principal          = var.workloads_ou_arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_principal_association" "infrastructure_ou" {
  principal          = var.infrastructure_ou_arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

# ------------------------------------------------------------------------------
# Accept pending spoke attachments (read-only discovery + an accepter per match).
# ------------------------------------------------------------------------------
data "aws_ec2_transit_gateway_vpc_attachments" "pending" {
  count = var.accept_vpc_attachments ? 1 : 0

  filter {
    name   = "transit-gateway-id"
    values = [aws_ec2_transit_gateway.this.id]
  }

  filter {
    name   = "state"
    values = ["pendingAcceptance"]
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "this" {
  for_each = var.accept_vpc_attachments ? toset(data.aws_ec2_transit_gateway_vpc_attachments.pending[0].ids) : toset([])

  transit_gateway_attachment_id = each.value

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Cross-region peering (PLAN 5.2)
# ------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  count = var.peering.role == "requester" ? 1 : 0

  transit_gateway_id      = aws_ec2_transit_gateway.this.id
  peer_transit_gateway_id = var.peering.peer_transit_gateway_id
  peer_region             = var.peering.peer_region
  peer_account_id         = coalesce(var.peering.peer_account_id, data.aws_caller_identity.current[0].account_id)

  tags = var.tags
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  count = var.peering.role == "accepter" ? 1 : 0

  transit_gateway_attachment_id = var.peering.accepter_attachment_id

  tags = var.tags
}

data "aws_caller_identity" "current" {
  count = var.peering.role == "requester" ? 1 : 0
}

# ------------------------------------------------------------------------------
# Hybrid connectivity (PLAN 5.6): optional, no real peer to connect to yet.
# ------------------------------------------------------------------------------
resource "aws_customer_gateway" "this" {
  count = var.enable_site_to_site_vpn ? 1 : 0

  bgp_asn    = var.customer_gateway_bgp_asn
  ip_address = var.customer_gateway_ip
  type       = "ipsec.1"

  tags = var.tags
}

resource "aws_vpn_connection" "this" {
  count = var.enable_site_to_site_vpn ? 1 : 0

  customer_gateway_id = aws_customer_gateway.this[0].id
  transit_gateway_id  = aws_ec2_transit_gateway.this.id
  type                = "ipsec.1"

  tags = var.tags
}

resource "aws_dx_gateway_association" "this" {
  count = var.enable_direct_connect_gateway_association ? 1 : 0

  dx_gateway_id         = var.direct_connect_gateway_id
  associated_gateway_id = aws_ec2_transit_gateway.this.id
  allowed_prefixes      = var.direct_connect_gateway_allowed_prefixes
}
