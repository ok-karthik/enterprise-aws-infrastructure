# Central egress/inspection VPC (PLAN 5.3), applied in network-hub, per region: NAT gateways (one per AZ) and
# AWS Network Firewall behind a stateful domain allow-list. Spoke VPCs lose their own NAT gateways and send
# 0.0.0.0/0 to the transit gateway instead (network/vpc's egress_mode = "central", network/tgw-attachment's
# egress_route_cidr), landing here.
#
# Three subnet tiers per AZ (the standard AWS centralized-inspection layout):
#   tgw       -- where this VPC's OWN transit gateway attachment lives; spoke traffic arrives here.
#   firewall  -- Network Firewall's VPC endpoints (one per AZ); traffic is inspected here.
#   public    -- the NAT gateways and the internet gateway route.
# tgw -> firewall -> public -> NAT -> internet, and the reverse for return traffic.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  az_count = length(var.azs)

  # 3 tiers x az_count subnets, newbits = 4 (up to 16 subnets: enough for 5 AZs x 3 tiers). vpc_cidr should be
  # sized so a /4-larger subnet is still a sensible size (e.g. a /20 VPC gives /24 subnets).
  subnet_cidrs          = [for i in range(local.az_count * 3) : cidrsubnet(var.vpc_cidr, 4, i)]
  tgw_subnet_cidrs      = slice(local.subnet_cidrs, 0, local.az_count)
  firewall_subnet_cidrs = slice(local.subnet_cidrs, local.az_count, local.az_count * 2)
  public_subnet_cidrs   = slice(local.subnet_cidrs, local.az_count * 2, local.az_count * 3)

  azs_by_index = { for i, az in var.azs : az => i }

  tags = merge({ Service = "network-inspection-egress", ManagedBy = "Terragrunt-Wrapper" }, var.tags)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = var.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-igw" })
}

resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  log_destination_type = "s3"
  log_destination      = "arn:${data.aws_partition.current.partition}:s3:::${var.log_archive_bucket_name}/${var.name}/vpc-flow-logs/"
  traffic_type         = "ALL"

  tags = local.tags
}

resource "aws_subnet" "tgw" {
  for_each = local.azs_by_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.tgw_subnet_cidrs[each.value]

  tags = merge(local.tags, { Name = "${var.name}-tgw-${each.key}", Tier = "tgw" })
}

resource "aws_subnet" "firewall" {
  for_each = local.azs_by_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.firewall_subnet_cidrs[each.value]

  tags = merge(local.tags, { Name = "${var.name}-firewall-${each.key}", Tier = "firewall" })
}

resource "aws_subnet" "public" {
  for_each = local.azs_by_index

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = local.public_subnet_cidrs[each.value]
  map_public_ip_on_launch = false # NAT gateway EIPs are explicit below; no other resource lives here

  tags = merge(local.tags, { Name = "${var.name}-public-${each.key}", Tier = "public" })
}

# ------------------------------------------------------------------------------
# NAT gateways: one per AZ, in that AZ's public subnet.
# ------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  for_each = local.azs_by_index

  domain = "vpc"

  tags = merge(local.tags, { Name = "${var.name}-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each = local.azs_by_index

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(local.tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

# ------------------------------------------------------------------------------
# Network Firewall: a stateful domain allow-list, strict rule order (anything not explicitly allowed is
# dropped once the connection is established).
# ------------------------------------------------------------------------------
resource "aws_kms_key" "firewall" {
  description             = "Encrypts the Network Firewall rule groups, policy and firewall in ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIamPolicies"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowNetworkFirewallToUseTheKey"
        Effect    = "Allow"
        Principal = { Service = "network-firewall.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
      },
    ]
  })

  tags = local.tags
}

resource "aws_kms_alias" "firewall" {
  name          = "alias/${var.name}-firewall"
  target_key_id = aws_kms_key.firewall.key_id
}

resource "aws_networkfirewall_rule_group" "domain_allow_list" {
  name     = "${var.name}-domain-allow-list"
  type     = "STATEFUL"
  capacity = 100

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        targets              = var.domain_allow_list
      }
    }
  }

  encryption_configuration {
    type   = "CUSTOMER_KMS"
    key_id = aws_kms_key.firewall.arn
  }

  tags = local.tags
}

resource "aws_networkfirewall_rule_group" "additional" {
  count = var.additional_suricata_rules != "" ? 1 : 0

  name     = "${var.name}-additional-rules"
  type     = "STATEFUL"
  capacity = 100

  rule_group {
    rules_source {
      rules_string = var.additional_suricata_rules
    }
  }

  encryption_configuration {
    type   = "CUSTOMER_KMS"
    key_id = aws_kms_key.firewall.arn
  }

  tags = local.tags
}

resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.name}-policy"

  encryption_configuration {
    type   = "CUSTOMER_KMS"
    key_id = aws_kms_key.firewall.arn
  }

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    # STRICT_ORDER + drop_established: only the domain allow-list (and additional_suricata_rules, if any)
    # explicitly pass traffic; everything else is dropped once the connection is established.
    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }
    stateful_default_actions = ["aws:drop_established"]

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.domain_allow_list.arn
      priority     = 1
    }

    dynamic "stateful_rule_group_reference" {
      for_each = var.additional_suricata_rules != "" ? [1] : []
      content {
        resource_arn = aws_networkfirewall_rule_group.additional[0].arn
        priority     = 2
      }
    }
  }

  tags = local.tags
}

resource "aws_networkfirewall_firewall" "this" {
  name                = var.name
  vpc_id              = aws_vpc.this.id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  delete_protection   = true

  encryption_configuration {
    type   = "CUSTOMER_KMS"
    key_id = aws_kms_key.firewall.arn
  }

  dynamic "subnet_mapping" {
    for_each = local.azs_by_index
    content {
      subnet_id = aws_subnet.firewall[subnet_mapping.key].id
    }
  }

  tags = local.tags
}

resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn

  logging_configuration {
    log_destination_config {
      log_destination_type = "S3"
      log_type             = "ALERT"
      log_destination = {
        bucketName = var.log_archive_bucket_name
        prefix     = "${var.name}/alert"
      }
    }

    log_destination_config {
      log_destination_type = "S3"
      log_type             = "FLOW"
      log_destination = {
        bucketName = var.log_archive_bucket_name
        prefix     = "${var.name}/flow"
      }
    }
  }
}

# ------------------------------------------------------------------------------
# This VPC's own transit gateway attachment, in the tgw subnets, with appliance mode ON (a flow must keep
# using the same firewall endpoint, not bounce between AZs mid-connection). Associates/propagates into the
# transit gateway's "inspection" route table (network/transit-gateway).
# ------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.this.id
  subnet_ids         = [for s in aws_subnet.tgw : s.id]

  appliance_mode_support = "enable"

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = local.tags
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.inspection_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.inspection_route_table_id
}

# ------------------------------------------------------------------------------
# Routing: tgw subnet -> firewall endpoint -> public subnet (NAT) -> internet, and back.
# ------------------------------------------------------------------------------
locals {
  # AZ => the Network Firewall VPC endpoint id in that AZ's firewall subnet.
  firewall_endpoint_by_az = {
    for ss in aws_networkfirewall_firewall.this.firewall_status[0].sync_states :
    ss.availability_zone => ss.attachment[0].endpoint_id
  }
}

resource "aws_route_table" "tgw" {
  for_each = local.azs_by_index

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-tgw-rt-${each.key}" })
}

resource "aws_route" "tgw_to_firewall" {
  for_each = local.azs_by_index

  route_table_id         = aws_route_table.tgw[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_by_az[each.key]
}

resource "aws_route_table_association" "tgw" {
  for_each = local.azs_by_index

  subnet_id      = aws_subnet.tgw[each.key].id
  route_table_id = aws_route_table.tgw[each.key].id
}

resource "aws_route_table" "public" {
  for_each = local.azs_by_index

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-public-rt-${each.key}" })
}

# Return traffic from the internet also passes back through the firewall before reaching the tgw subnet.
resource "aws_route" "public_to_firewall" {
  for_each = local.azs_by_index

  route_table_id         = aws_route_table.public[each.key].id
  destination_cidr_block = var.vpc_cidr
  vpc_endpoint_id        = local.firewall_endpoint_by_az[each.key]
}

resource "aws_route" "public_to_internet" {
  for_each = local.azs_by_index

  route_table_id         = aws_route_table.public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = local.azs_by_index

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[each.key].id
}

resource "aws_route_table" "firewall" {
  for_each = local.azs_by_index

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-firewall-rt-${each.key}" })
}

resource "aws_route" "firewall_to_nat" {
  for_each = local.azs_by_index

  route_table_id         = aws_route_table.firewall[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "firewall" {
  for_each = local.azs_by_index

  subnet_id      = aws_subnet.firewall[each.key].id
  route_table_id = aws_route_table.firewall[each.key].id
}
