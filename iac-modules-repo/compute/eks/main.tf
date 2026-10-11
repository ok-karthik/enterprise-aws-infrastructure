terraform {
  required_version = ">= 1.9.0" # cross-variable validation (api_allowed_cidrs) needs 1.9+
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.19.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # --- HARDENING: Control Plane Endpoint Access ---
  # Nodes always reach the API privately. Public access is off by default and, when enabled,
  # must come with an explicit CIDR allow-list (enforced by a validation in variables.tf).
  # There is deliberately no "0.0.0.0/0" fallback: an empty list must never mean "open to all".
  endpoint_private_access      = true
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access ? var.api_allowed_cidrs : null

  # --- GOVERNANCE: Standard Node Groups ---
  eks_managed_node_groups = {
    spot_nodes = {
      ami_type       = var.ami_type
      instance_types = var.instance_types
      capacity_type  = "SPOT"

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      # Force custom launch template to ensure GP3 and IMDSv2 overrides
      use_custom_launch_template = true
      disk_size                  = null

      # --- HARDENING: Enforce IMDSv2 with hop limit = 1 ---
      # Prevents pod-level SSRF / host namespace pivoting
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required" # IMDSv2 only
        http_put_response_hop_limit = 1
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = true # enforced by policy-library-repo/terraform/require_encryption.rego
            delete_on_termination = true
          }
        }
      }
    }
  }

  # --- EKS ADDONS: Managed Addons ---
  addons = merge(
    {
      vpc-cni = {
        most_recent = true
      }
      coredns = {
        most_recent = true
      }
      kube-proxy = {
        most_recent = true
      }
      aws-ebs-csi-driver = {
        most_recent = true
      }
      eks-pod-identity-agent = {
        most_recent = true
      }
    },
    var.cluster_addons
  )

  # --- KARPENTER: Node Security Group Discovery Tag ---
  node_security_group_tags = merge(
    {
      "karpenter.sh/discovery" = var.cluster_name
    },
    var.node_security_group_tags
  )

  # --- GOVERNANCE: Mandatory Tagging ---
  tags = merge(
    {
      ManagedBy     = "Terragrunt-Wrapper"
      SecurityLevel = "High"
      K8sAccess     = "IAM-Only"
      Service       = "compute-eks" # Required by FinOps tag policy
    },
    var.tags
  )

  # --- SECURITY: Control Plane Hardening & Logging ---
  enabled_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_kms_key          = true
  enable_kms_key_rotation = true

  # CloudWatch Log Group KMS Encryption (CKV_AWS_158)
  cloudwatch_log_group_kms_key_id = module.eks.kms_key_arn
}

# --- KARPENTER: AWS Cloud Prerequisites (IAM, SQS, EventBridge) ---
module "karpenter" {
  count   = var.enable_karpenter ? 1 : 0
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.19.0"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  enable_spot_termination = true

  tags = merge(
    {
      Service = "compute-karpenter"
    },
    var.tags
  )
}

# ------------------------------------------------------------------------------
# Working-hours schedule (PLAN 9.5): scale the node group to zero at night, back up in the morning.
#
# It changes DESIRED size only. The upstream node group ignores desired_size drift
# (lifecycle ignore_changes), so the schedule causes no Terraform diff. min_size would drift, which is why
# min_size must be 0 (validated on the variable). Off by default (scale_schedule = null).
#
# What it does not do: the EKS control plane (about $0.10/h) keeps running, so only the node hours go down
# (weekdays 07-19 = 60 of 168 h, 64 % fewer node hours). It also only scales the managed node group
# "spot_nodes". Nodes Karpenter launched keep running, and the Karpenter controller pod loses its node when the
# group is at 0, so on a cluster with Karpenter enabled the schedule alone does not switch everything off.
# Known limit, nothing is built for it here.
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {
  count = var.scale_schedule == null ? 0 : 1
}

locals {
  node_group_name = try(split(":", module.eks.eks_managed_node_groups["spot_nodes"].node_group_id)[1], "")
  node_group_arn  = try(module.eks.eks_managed_node_groups["spot_nodes"].node_group_arn, "")
}

resource "aws_iam_role" "scheduler" {
  count = var.scale_schedule == null ? 0 : 1

  name = "${var.cluster_name}-nodegroup-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current[0].account_id } }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.scale_schedule == null ? 0 : 1

  name = "update-nodegroup-config"
  role = aws_iam_role.scheduler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:UpdateNodegroupConfig"
      Resource = local.node_group_arn
    }]
  })
}

resource "aws_scheduler_schedule" "down" {
  #checkov:skip=CKV_AWS_297: the payload is only a cluster name, a node group name and a number; no sensitive data, so the default AWS-owned key is enough
  count = var.scale_schedule == null ? 0 : 1

  name                         = "${var.cluster_name}-nodes-down"
  description                  = "Scale the spot_nodes node group to 0 (PLAN 9.5)"
  schedule_expression          = var.scale_schedule.down_cron
  schedule_expression_timezone = var.scale_schedule.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:eks:updateNodegroupConfig"
    role_arn = aws_iam_role.scheduler[0].arn
    input = jsonencode({
      ClusterName   = module.eks.cluster_name
      NodegroupName = local.node_group_name
      ScalingConfig = { DesiredSize = 0 }
    })

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}

resource "aws_scheduler_schedule" "up" {
  #checkov:skip=CKV_AWS_297: the payload is only a cluster name, a node group name and a number; no sensitive data, so the default AWS-owned key is enough
  count = var.scale_schedule == null ? 0 : 1

  name                         = "${var.cluster_name}-nodes-up"
  description                  = "Scale the spot_nodes node group back up (PLAN 9.5)"
  schedule_expression          = var.scale_schedule.up_cron
  schedule_expression_timezone = var.scale_schedule.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:eks:updateNodegroupConfig"
    role_arn = aws_iam_role.scheduler[0].arn
    input = jsonencode({
      ClusterName   = module.eks.cluster_name
      NodegroupName = local.node_group_name
      ScalingConfig = { DesiredSize = var.scale_schedule.up_desired }
    })

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}
