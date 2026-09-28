terraform {
  required_version = ">= 1.9.0" # cross-variable validation (cidr vs. ipv4_ipam_pool_id) needs 1.9+
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  # The default-ACL ingress rule below needs a CIDR to allow at CONFIG-WRITE time. In literal-cidr mode that
  # is var.cidr, known up front. In IPAM mode (PLAN 5.1) the real VPC CIDR is only known after AWS allocates
  # it at apply, so unless the caller supplies the tighter range it already knows (var.default_network_acl_allow_cidr,
  # normally the env pool's own range once a first apply has revealed it), this widens to the whole platform
  # address space (network/ipam's top_level_cidr default). Defense in depth: security groups, not this NACL,
  # are the primary control.
  default_network_acl_allow_cidr = var.default_network_acl_allow_cidr != "" ? var.default_network_acl_allow_cidr : (var.cidr != "" ? var.cidr : "10.0.0.0/8")
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name

  # Exactly one of these two modes is set (var.cidr's validation enforces it): a literal CIDR, or a
  # request against an IPAM pool (network/ipam, PLAN 5.1). The upstream module treats "" and null the
  # same as "not set" for these three inputs.
  cidr                = var.cidr != "" ? var.cidr : null
  ipv4_ipam_pool_id   = var.ipv4_ipam_pool_id != "" ? var.ipv4_ipam_pool_id : null
  ipv4_netmask_length = var.ipv4_netmask_length

  azs              = var.azs
  private_subnets  = var.private_subnets
  public_subnets   = var.public_subnets
  database_subnets = var.database_subnets

  create_database_subnet_group = length(var.database_subnets) > 0

  # egress_mode = "central" (PLAN 5.3) always wins: no NAT gateways here, whatever enable_nat_gateway says.
  enable_nat_gateway = var.egress_mode == "local-nat" ? var.enable_nat_gateway : false
  single_nat_gateway = var.single_nat_gateway

  # --- AUTOMATION: EKS Subnet Tagging ---
  # These tags are required for the EKS Load Balancer Controller to discover subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = merge(
    {
      "kubernetes.io/role/internal-elb" = 1
    },
    var.cluster_name != "" ? { "kubernetes.io/cluster/${var.cluster_name}" = "shared" } : {}
  )

  # --- GOVERNANCE: Mandatory Tagging ---
  tags = merge(
    {
      ManagedBy     = "Terragrunt-Wrapper"
      SecurityLevel = "High"
      Compliance    = "SOC2-Prototype"
      Service       = "network-vpc" # Required by FinOps tag policy
    },
    var.tags
  )

  # --- SECURITY: VPC Flow Logs (PLAN 5.7) ---
  # This module's own flow log always goes to CloudWatch, unless "s3" is the ONLY entry in
  # flow_log_destinations (aws_flow_log.this below covers S3, "as well as" or "instead of" this one).
  enable_flow_log                      = contains(var.flow_log_destinations, "cloudwatch")
  create_flow_log_cloudwatch_log_group = contains(var.flow_log_destinations, "cloudwatch")
  create_flow_log_cloudwatch_iam_role  = contains(var.flow_log_destinations, "cloudwatch")
  flow_log_max_aggregation_interval    = 60

  # --- SECURITY: Hardening Defaults ---
  manage_default_network_acl = true
  default_network_acl_ingress = [
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = local.default_network_acl_allow_cidr # Only allow traffic from within the VPC by default
    }
  ]
  default_network_acl_egress = [
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "0.0.0.0/0" # Allow all outbound (Required for updates/bootstrap)
    }
  ]

  manage_default_security_group  = true
  default_security_group_ingress = [] # Deny all ingress to default SG
  default_security_group_egress  = [] # Deny all egress from default SG
}

# --- SECURITY: VPC Flow Logs to S3 (PLAN 5.7), "as well as" or "instead of" the CloudWatch one above ---
resource "aws_iam_role" "flow_log_s3" {
  count = contains(var.flow_log_destinations, "s3") ? 1 : 0

  name = "${var.name}-flow-log-s3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowVpcFlowLogsToAssume"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_flow_log" "s3" {
  count = contains(var.flow_log_destinations, "s3") ? 1 : 0

  vpc_id               = module.vpc.vpc_id
  log_destination_type = "s3"
  log_destination      = var.flow_log_s3_destination_arn
  iam_role_arn         = aws_iam_role.flow_log_s3[0].arn
  traffic_type         = "ALL"

  tags = var.tags
}

# --- SECURITY: VPC Block Public Access exclusion, only for designated ingress subnets (PLAN 5.7) ---
# Account-wide VPC BPA (governance/account-baseline) blocks internet ingress by default; this VPC's public
# subnets (never the private/database ones) are excluded explicitly, and only when var.exclude_public_subnets_from_account_bpa
# is set -- the account default stays "blocked" for every other VPC/subnet. for_each keys off the INDEX into
# var.public_subnets (known at plan time from the config), not module.vpc.public_subnets itself (the real
# subnet ids, unknown until the upstream module actually creates them in the same plan).
resource "aws_vpc_block_public_access_exclusion" "public_subnets" {
  for_each = var.exclude_public_subnets_from_account_bpa ? { for i, cidr in var.public_subnets : tostring(i) => cidr } : {}

  subnet_id                       = module.vpc.public_subnets[tonumber(each.key)]
  internet_gateway_exclusion_mode = "allow-bidirectional"
}

# --- DISCOVERY CONTRACT (Phase 18.1): SSM Parameter Store Service Catalog ---
resource "aws_ssm_parameter" "vpc_id" {
  #checkov:skip=CKV2_AWS_34: "Platform discovery catalog parameter contains non-sensitive metadata"
  count       = var.publish_ssm_parameters && var.env != "" && var.region != "" ? 1 : 0
  name        = "/platform/${var.env}/${var.region}/vpc/id"
  description = "Platform Discovery Contract: VPC ID for ${var.env} in ${var.region}"
  type        = "String"
  value       = module.vpc.vpc_id

  tags = merge(
    {
      Service   = "network-vpc"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

resource "aws_ssm_parameter" "database_subnets" {
  #checkov:skip=CKV2_AWS_34: "Platform discovery catalog parameter contains non-sensitive metadata"
  count       = var.publish_ssm_parameters && var.env != "" && var.region != "" && length(module.vpc.database_subnets) > 0 ? 1 : 0
  name        = "/platform/${var.env}/${var.region}/vpc/database_subnets"
  description = "Platform Discovery Contract: Database Subnet IDs for ${var.env} in ${var.region}"
  type        = "StringList"
  value       = join(",", module.vpc.database_subnets)

  tags = merge(
    {
      Service   = "network-vpc"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}
