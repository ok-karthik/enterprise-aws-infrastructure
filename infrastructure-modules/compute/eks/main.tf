terraform {
  required_version = ">= 1.5.0"
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
  # Nodes always reach the API privately; public access is configurable with CIDR restrictions.
  endpoint_private_access      = true
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = length(var.api_allowed_cidrs) > 0 ? var.api_allowed_cidrs : (var.cluster_endpoint_public_access ? ["0.0.0.0/0"] : null)

  # --- GOVERNANCE: Standard Node Groups ---
  eks_managed_node_groups = {
    spot_nodes = {
      ami_type       = "AL2023_x86_64_STANDARD"
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

# --- DISCOVERY CONTRACT (Phase 18.1): SSM Parameter Store Service Catalog ---
resource "aws_ssm_parameter" "cluster_name" {
  count       = var.publish_ssm_parameters && var.env != "" && var.region != "" ? 1 : 0
  name        = "/platform/${var.env}/${var.region}/eks/cluster_name"
  description = "Platform Discovery Contract: EKS Cluster Name for ${var.env} in ${var.region}"
  type        = "String"
  value       = module.eks.cluster_name

  tags = merge(
    {
      Service   = "compute-eks"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

resource "aws_ssm_parameter" "oidc_provider_arn" {
  count       = var.publish_ssm_parameters && var.env != "" && var.region != "" ? 1 : 0
  name        = "/platform/${var.env}/${var.region}/eks/oidc_provider_arn"
  description = "Platform Discovery Contract: EKS OIDC Provider ARN for ${var.env} in ${var.region}"
  type        = "String"
  value       = module.eks.oidc_provider_arn

  tags = merge(
    {
      Service   = "compute-eks"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}
