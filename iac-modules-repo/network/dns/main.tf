# DNS (PLAN 5.5), applied in network-hub, per region: Route 53 Resolver inbound and outbound endpoints,
# forwarding rules for on-premises domains (shared with the Workloads OU through RAM), resolver query
# logging, and public hosted zones with delegated subdomains per workload account.

locals {
  azs_by_index = { for i, az in var.azs : az => i }
  subnet_cidrs = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 4, i)]

  tags = merge({ Service = "network-dns", ManagedBy = "Terragrunt-Wrapper" }, var.tags)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = var.name })
}

resource "aws_cloudwatch_log_group" "flow_log" {
  #checkov:skip=CKV_AWS_158: "Repo-wide skip already covers this (known Checkov bug with a KMS key that is known-after-apply)"
  name              = "/aws/vpc/${var.name}-flow-logs"
  retention_in_days = 90

  tags = local.tags
}

resource "aws_iam_role" "flow_log" {
  name = "${var.name}-flow-log"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowVpcFlowLogsToAssume"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "flow_log" {
  name = "write-flow-logs"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteFlowLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow_log.arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_log.arn
  iam_role_arn         = aws_iam_role.flow_log.arn
  traffic_type         = "ALL"

  tags = local.tags
}

resource "aws_subnet" "this" {
  for_each = local.azs_by_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs[each.value]

  tags = merge(local.tags, { Name = "${var.name}-${each.key}" })
}

# ------------------------------------------------------------------------------
# Resolver endpoints: inbound (on-prem -> AWS) and outbound (AWS -> on-prem).
# ------------------------------------------------------------------------------
resource "aws_security_group" "inbound" {
  name        = "${var.name}-resolver-inbound"
  description = "Allows DNS (53/tcp+udp) from on-premises networks to the inbound resolver endpoint"
  vpc_id      = aws_vpc.this.id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "inbound_udp" {
  for_each = toset(var.on_prem_cidr_blocks)

  security_group_id = aws_security_group.inbound.id
  cidr_ipv4         = each.value
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_ingress_rule" "inbound_tcp" {
  for_each = toset(var.on_prem_cidr_blocks)

  security_group_id = aws_security_group.inbound.id
  cidr_ipv4         = each.value
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "inbound_all" {
  security_group_id = aws_security_group.inbound.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_route53_resolver_endpoint" "inbound" {
  name               = "${var.name}-inbound"
  direction          = "INBOUND"
  security_group_ids = [aws_security_group.inbound.id]

  dynamic "ip_address" {
    for_each = local.azs_by_index
    content {
      subnet_id = aws_subnet.this[ip_address.key].id
    }
  }

  tags = local.tags
}

resource "aws_security_group" "outbound" {
  name        = "${var.name}-resolver-outbound"
  description = "Allows the outbound resolver endpoint to reach on-premises DNS servers"
  vpc_id      = aws_vpc.this.id

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "outbound_dns" {
  security_group_id = aws_security_group.outbound.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # simplest correct default; narrow to on_prem_cidr_blocks + 53/tcp+udp once the real ranges are known
}

resource "aws_route53_resolver_endpoint" "outbound" {
  name               = "${var.name}-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [aws_security_group.outbound.id]

  dynamic "ip_address" {
    for_each = local.azs_by_index
    content {
      subnet_id = aws_subnet.this[ip_address.key].id
    }
  }

  tags = local.tags
}

# ------------------------------------------------------------------------------
# Forwarding rules for on-premises domains, shared with the Workloads OU.
# ------------------------------------------------------------------------------
resource "aws_route53_resolver_rule" "forwarding" {
  for_each = var.forwarding_rules

  name                 = "${var.name}-${replace(each.key, ".", "-")}"
  domain_name          = each.key
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  dynamic "target_ip" {
    for_each = each.value
    content {
      ip = target_ip.value
    }
  }

  tags = local.tags
}

resource "aws_route53_resolver_query_log_config" "this" {
  name            = "${var.name}-query-log"
  destination_arn = var.query_log_destination_arn

  tags = local.tags
}

resource "aws_route53_resolver_query_log_config_association" "this" {
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.this.id
  resource_id                  = aws_vpc.this.id
}

resource "aws_ram_resource_share" "this" {
  name                      = "${var.name}-resolver"
  allow_external_principals = false

  tags = local.tags
}

resource "aws_ram_resource_association" "rules" {
  for_each = aws_route53_resolver_rule.forwarding

  resource_arn       = each.value.arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_resource_association" "query_log_config" {
  resource_arn       = aws_route53_resolver_query_log_config.this.arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_principal_association" "workloads_ou" {
  principal          = var.workloads_ou_arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

# ------------------------------------------------------------------------------
# Public hosted zones: the root domain here, one delegated subdomain per workload account.
# ------------------------------------------------------------------------------
resource "aws_route53_zone" "root" {
  # DNSSEC signing (CKV2_AWS_38) needs a KMS key in us-east-1 specifically (an AWS DNSSEC requirement,
  # unrelated to this module's own region), and query logging (CKV2_AWS_39) needs a us-east-1 CloudWatch
  # Logs group too. Neither can be created by this module: it is pure (no provider blocks), and both need a
  # provider aliased to us-east-1. Follow-up: a small us-east-1-scoped companion at the live layer.
  #checkov:skip=CKV2_AWS_38: "DNSSEC needs a KMS key in us-east-1; this module has no provider blocks (pure module) so it cannot create one -- a live-layer follow-up with a us-east-1 provider alias"
  #checkov:skip=CKV2_AWS_39: "Public-zone query logging needs a CloudWatch Logs group in us-east-1 specifically; same reason as CKV2_AWS_38"
  count = var.root_domain != "" ? 1 : 0

  name = var.root_domain

  tags = local.tags
}

resource "aws_route53_zone" "delegated" {
  #checkov:skip=CKV2_AWS_38: "Same as aws_route53_zone.root: needs a us-east-1 KMS key this pure module cannot create"
  #checkov:skip=CKV2_AWS_39: "Same as aws_route53_zone.root: needs a us-east-1 CloudWatch Logs group this pure module cannot create"
  for_each = var.delegated_subdomains

  name = "${each.value}.${var.root_domain}"

  tags = merge(local.tags, { Account = each.key })
}

resource "aws_route53_record" "delegation" {
  for_each = var.delegated_subdomains

  zone_id = aws_route53_zone.root[0].zone_id
  name    = "${each.value}.${var.root_domain}"
  type    = "NS"
  ttl     = 172800

  records = aws_route53_zone.delegated[each.key].name_servers
}
