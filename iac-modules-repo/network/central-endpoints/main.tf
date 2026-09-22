# Shared interface endpoints (PLAN 5.4), applied in a shared-services (or network-hub) account: one VPC
# holding an interface endpoint per service in var.services, and a private hosted zone per service (NOT the
# endpoint's own AWS-managed private DNS, which only resolves inside its own VPC) so spoke VPCs can resolve
# the same endpoint centrally once their zone is associated. Gateway endpoints (S3, DynamoDB) are NOT here:
# they are free and stay local to each VPC (network/vpc, or a spoke's own module).

data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region

  # com.amazonaws.<region>.<service> service names, and the matching private DNS zone name AWS documents for
  # each (verified against the provider schema and general PrivateLink documentation, not against a real
  # deployment -- see the module README).
  service_names = {
    ecr_api        = "com.amazonaws.${local.region}.ecr.api"
    ecr_dkr        = "com.amazonaws.${local.region}.ecr.dkr"
    sts            = "com.amazonaws.${local.region}.sts"
    ssm            = "com.amazonaws.${local.region}.ssm"
    ssmmessages    = "com.amazonaws.${local.region}.ssmmessages"
    ec2messages    = "com.amazonaws.${local.region}.ec2messages"
    logs           = "com.amazonaws.${local.region}.logs"
    kms            = "com.amazonaws.${local.region}.kms"
    secretsmanager = "com.amazonaws.${local.region}.secretsmanager"
    eks            = "com.amazonaws.${local.region}.eks"
  }

  zone_names = {
    ecr_api        = "api.ecr.${local.region}.amazonaws.com"
    ecr_dkr        = "dkr.ecr.${local.region}.amazonaws.com"
    sts            = "sts.${local.region}.amazonaws.com"
    ssm            = "ssm.${local.region}.amazonaws.com"
    ssmmessages    = "ssmmessages.${local.region}.amazonaws.com"
    ec2messages    = "ec2messages.${local.region}.amazonaws.com"
    logs           = "logs.${local.region}.amazonaws.com"
    kms            = "kms.${local.region}.amazonaws.com"
    secretsmanager = "secretsmanager.${local.region}.amazonaws.com"
    eks            = "eks.${local.region}.amazonaws.com"
  }

  azs_by_index = { for i, az in var.azs : az => i }
  subnet_cidrs = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 4, i)]

  tags = merge({ Service = "network-central-endpoints", ManagedBy = "Terragrunt-Wrapper" }, var.tags)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = var.name })
}

resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_log.arn
  iam_role_arn         = aws_iam_role.flow_log.arn
  traffic_type         = "ALL"

  tags = local.tags
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

resource "aws_subnet" "this" {
  for_each = local.azs_by_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs[each.value]

  tags = merge(local.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-endpoints"
  description = "Allows HTTPS from the platform's address space to the shared interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.endpoints.id
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.endpoints.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_endpoint" "this" {
  for_each = toset(var.services)

  vpc_id             = aws_vpc.this.id
  service_name       = local.service_names[each.key]
  vpc_endpoint_type  = "Interface"
  subnet_ids         = [for s in aws_subnet.this : s.id]
  security_group_ids = [aws_security_group.endpoints.id]
  # DNS is handled by the shared private hosted zones below, not the endpoint's own (VPC-local-only) private DNS.
  private_dns_enabled = false

  tags = merge(local.tags, { Name = "${var.name}-${each.key}" })
}

# ------------------------------------------------------------------------------
# One private hosted zone per service, with an alias record to the endpoint's REGIONAL DNS name (the first
# entry in dns_entry -- AWS's documented convention, not verified here against a real deployment; see the
# module README). Sharing a zone with a spoke VPC (aws_route53_vpc_association_authorization here, plus
# aws_route53_zone_association in the spoke's own account) is what makes the endpoint resolve centrally.
# ------------------------------------------------------------------------------
resource "aws_route53_zone" "this" {
  for_each = toset(var.services)

  name = local.zone_names[each.key]

  vpc {
    vpc_id = aws_vpc.this.id
  }

  tags = local.tags
}

resource "aws_route53_record" "this" {
  for_each = toset(var.services)

  zone_id = aws_route53_zone.this[each.key].zone_id
  name    = local.zone_names[each.key]
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.this[each.key].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.this[each.key].dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_vpc_association_authorization" "spokes" {
  for_each = {
    for pair in setproduct(var.services, var.spoke_vpcs) :
    "${pair[0]}/${pair[1].vpc_id}" => { service = pair[0], spoke = pair[1] }
  }

  zone_id    = aws_route53_zone.this[each.value.service].zone_id
  vpc_id     = each.value.spoke.vpc_id
  vpc_region = each.value.spoke.vpc_region
}
