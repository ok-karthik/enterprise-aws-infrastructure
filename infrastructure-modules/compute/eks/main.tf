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

  # --- v21 API: 'cluster_name' was renamed to 'name', 'cluster_version' → 'kubernetes_version' ---
  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids


  # --- GOVERNANCE: Standard Node Groups ---
  # Every cluster in the organization uses Spot Managed Node Groups to save costs.
  eks_managed_node_groups = {
    spot_nodes = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.instance_types
      capacity_type  = "SPOT"

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      # Force custom launch template to ensure GP3 overrides defaults
      use_custom_launch_template = true
      disk_size                  = null

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

  # --- EKS ADDONS: Pod Identity Agent ---
  cluster_addons = merge(
    {
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

  # --- SECURITY: Control Plane Hardening ---
  # Resolves security scan findings by enabling audit logs and secret encryption.
  enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  create_kms_key          = true
  enable_kms_key_rotation = true

  # (Secrets are automatically encrypted by the module when create_kms_key is true)

  # --- SECURITY: Encrypt CloudWatch Log Group (Resolves CKV_AWS_158) ---
  cloudwatch_log_group_kms_key_id = module.eks.kms_key_arn
}

# --- KARPENTER: AWS Cloud Prerequisites (IAM, SQS, EventBridge) ---
module "karpenter" {
  count   = var.enable_karpenter ? 1 : 0
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.19.0"

  cluster_name = module.eks.cluster_name

  # Enable Pod Identity for Karpenter controller
  enable_pod_identity             = true
  create_pod_identity_association = true

  # Attach additional policies to Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # Interruption handling: Creates SQS queue and EventBridge rules for Spot interruptions
  enable_spot_termination = true

  tags = merge(
    {
      Service = "compute-karpenter"
    },
    var.tags
  )
}
