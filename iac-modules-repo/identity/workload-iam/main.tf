terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  role_name = lower("${var.team_name}-${var.app_name}-${var.env}")
}

# NOTE: this capability is currently a documented stub — it declares the module
# interface the scaffolder renders against, but provisions no identity yet.
#
# What it should become, once the cluster's OIDC issuer or Pod Identity is bound:
# an IAM role with an assume-role policy scoped to the workload's Kubernetes service
# account plus a least-privilege policy composed from the other capabilities the
# service requested (e.g. S3 access only if it requested s3, RDS access only if
# it requested postgres).
#
# Until then, requesting workload-iam produces valid Terraform that creates nothing,
# which is honest — as opposed to creating an over-permissive role.
