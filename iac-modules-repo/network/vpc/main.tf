terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name
  cidr = var.cidr

  azs              = var.azs
  private_subnets  = var.private_subnets
  public_subnets   = var.public_subnets
  database_subnets = var.database_subnets

  create_database_subnet_group = length(var.database_subnets) > 0

  enable_nat_gateway = var.enable_nat_gateway
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

  # --- SECURITY: VPC Flow Logs ---
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
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
      cidr_block = var.cidr # Only allow traffic from within the VPC by default
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

# --- DISCOVERY CONTRACT (Phase 18.1): SSM Parameter Store Service Catalog ---
resource "aws_ssm_parameter" "vpc_id" {
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
