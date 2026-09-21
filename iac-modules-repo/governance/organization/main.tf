terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. AWS Organizations Organizational Units (OUs)
# ------------------------------------------------------------------------------
resource "aws_organizations_organizational_unit" "production" {
  count     = var.root_id != "" ? 1 : 0
  name      = "Production"
  parent_id = var.root_id

  tags = merge(
    {
      Service   = "governance-organization"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

resource "aws_organizations_organizational_unit" "non_production" {
  count     = var.root_id != "" ? 1 : 0
  name      = "NonProduction"
  parent_id = var.root_id

  tags = merge(
    {
      Service   = "governance-organization"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

# ------------------------------------------------------------------------------
# 2. Service Control Policies (SCPs)
# ------------------------------------------------------------------------------
resource "aws_organizations_policy" "deny_leave_org" {
  count       = var.root_id != "" ? 1 : 0
  name        = "deny-leave-organization"
  description = "No account may remove itself from the organization"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyLeaveOrganization"
      Effect   = "Deny"
      Action   = "organizations:LeaveOrganization"
      Resource = "*"
    }]
  })

  tags = merge(
    {
      Service   = "governance-organization"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

resource "aws_organizations_policy" "deny_disable_cloudtrail" {
  count       = var.root_id != "" ? 1 : 0
  name        = "deny-disable-cloudtrail"
  description = "No principal may stop or delete the organization-wide CloudTrail audit trail"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyCloudTrailTampering"
      Effect = "Deny"
      Action = [
        "cloudtrail:StopLogging",
        "cloudtrail:DeleteTrail",
        "cloudtrail:UpdateTrail"
      ]
      Resource = "*"
    }]
  })

  tags = merge(
    {
      Service   = "governance-organization"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

locals {
  # Global services that have no regional endpoint (or only live in us-east-1) and must keep
  # working whatever region is being requested. Based on AWS's published "deny access based on
  # requested Region" example SCP; extend with var.additional_region_exempt_actions.
  region_exempt_actions = distinct(concat(
    [
      "account:*",
      "aws-portal:*",
      "billing:*",
      "budgets:*",
      "ce:*",
      "cloudfront:*",
      "cur:*",
      "fms:*",
      "globalaccelerator:*",
      "health:*",
      "iam:*",
      "organizations:*",
      "pricing:*",
      "route53:*",
      "route53domains:*",
      "shield:*",
      "sts:*",
      "support:*",
      "trustedadvisor:*",
      "waf:*",
      "waf-regional:*",
      "wafv2:*",
    ],
    var.additional_region_exempt_actions
  ))
}

moved {
  from = aws_organizations_policy.deny_outside_eu_central_1
  to   = aws_organizations_policy.deny_unapproved_regions
}

resource "aws_organizations_policy" "deny_unapproved_regions" {
  count       = var.root_id != "" ? 1 : 0
  name        = "deny-unapproved-regions"
  description = "Data residency control: deny requests to any region outside var.allowed_regions, except global services"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyUnapprovedRegions"
      Effect    = "Deny"
      NotAction = local.region_exempt_actions
      Resource  = "*"
      Condition = {
        StringNotEquals = { "aws:RequestedRegion" = var.allowed_regions }
      }
    }]
  })

  tags = merge(
    {
      Service   = "governance-organization"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

resource "aws_organizations_policy_attachment" "production_guardrails" {
  # Static keys: policy IDs are only known after apply and cannot be for_each keys themselves.
  for_each = var.root_id != "" ? {
    deny_leave_org          = aws_organizations_policy.deny_leave_org[0].id
    deny_disable_cloudtrail = aws_organizations_policy.deny_disable_cloudtrail[0].id
    deny_unapproved_regions = aws_organizations_policy.deny_unapproved_regions[0].id
  } : {}

  policy_id = each.value
  target_id = aws_organizations_organizational_unit.production[0].id
}

resource "aws_organizations_policy_attachment" "non_production_guardrails" {
  # Static keys: policy IDs are only known after apply and cannot be for_each keys themselves.
  for_each = var.root_id != "" ? {
    deny_leave_org          = aws_organizations_policy.deny_leave_org[0].id
    deny_disable_cloudtrail = aws_organizations_policy.deny_disable_cloudtrail[0].id
    deny_unapproved_regions = aws_organizations_policy.deny_unapproved_regions[0].id
  } : {}

  policy_id = each.value
  target_id = aws_organizations_organizational_unit.non_production[0].id
}

# ------------------------------------------------------------------------------
# 3. ACK Cross-Account Hub/Spoke Trust (ack-cross-account.tf)
# ------------------------------------------------------------------------------
# The spoke trusts the hub: allows ACK controllers running in the hub EKS cluster
# to assume this role with sts:ExternalId verification.
resource "aws_iam_role" "ack_spoke" {
  count = var.hub_ack_controller_role_arn != "" ? 1 : 0
  name  = "ack-hub-controller-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.hub_ack_controller_role_arn }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = var.external_id }
      }
    }]
  })

  tags = merge(
    {
      Purpose   = "ack-cross-account"
      Service   = "governance-organization"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )

  lifecycle {
    precondition {
      condition     = var.hub_account_id == "" || strcontains(var.hub_ack_controller_role_arn, ":${var.hub_account_id}:")
      error_message = "hub_ack_controller_role_arn does not belong to hub_account_id."
    }
  }
}

# The spoke role used to carry AmazonS3FullAccess + IAMFullAccess, which let anything that could
# assume it (the ACK controller, or whoever compromises it) mint an admin role. It now gets one
# scoped inline policy, and every role it can create must carry the ack-tenant-boundary.
data "aws_caller_identity" "current" {
  count = var.hub_ack_controller_role_arn != "" ? 1 : 0
}

locals {
  ack_account_id    = try(data.aws_caller_identity.current[0].account_id, "")
  ack_bucket_arn    = "arn:aws:s3:::${var.ack_s3_bucket_prefix}*"
  ack_role_arn_glob = "arn:aws:iam::${local.ack_account_id}:role/${var.ack_role_path}*"
}

# Permissions boundary for every role ACK (or a tenant through ACK) creates. A boundary only
# ever narrows a role, so even if a tenant attaches AdministratorAccess to their role, the
# effective permissions stay inside this document.
resource "aws_iam_policy" "ack_tenant_boundary" {
  count       = var.hub_ack_controller_role_arn != "" ? 1 : 0
  name        = "ack-tenant-boundary"
  description = "Permissions boundary for roles created through ACK: S3 on prefixed buckets only, no IAM/org/identity changes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowPrefixedBuckets"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = [local.ack_bucket_arn, "${local.ack_bucket_arn}/*"]
      },
      {
        Sid      = "AllowKmsForS3"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = "*"
        Condition = {
          StringLike = { "kms:ViaService" = "s3.*.amazonaws.com" }
        }
      },
      {
        Sid    = "DenyPrivilegeEscalation"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateAccessKey",
          "iam:CreateLoginProfile",
          "iam:DeleteRolePermissionsBoundary",
          "iam:DeleteUserPermissionsBoundary",
          "iam:PutRolePermissionsBoundary",
          "iam:PutUserPermissionsBoundary",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "organizations:*",
          "account:*",
          "sso:*",
          "sso-directory:*",
          "cloudtrail:StopLogging",
          "cloudtrail:DeleteTrail",
          "cloudtrail:UpdateTrail"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    {
      Purpose   = "ack-cross-account"
      Service   = "governance-organization"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

resource "aws_iam_role_policy" "ack_spoke_scoped" {
  count = var.hub_ack_controller_role_arn != "" ? 1 : 0
  name  = "ack-scoped-permissions"
  role  = aws_iam_role.ack_spoke[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManagePrefixedBuckets"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:GetBucket*",
          "s3:PutBucket*",
          "s3:DeleteBucketPolicy",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration"
        ]
        Resource = local.ack_bucket_arn
      },
      {
        # s3:ListAllMyBuckets does not support resource-level scoping.
        Sid      = "ListBuckets"
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      },
      {
        Sid      = "CreateBoundedRoles"
        Effect   = "Allow"
        Action   = ["iam:CreateRole"]
        Resource = local.ack_role_arn_glob
        Condition = {
          StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.ack_tenant_boundary[0].arn }
        }
      },
      {
        # The boundary condition is checked against the target role's current boundary, so
        # these only work on roles that were created with (and still carry) the boundary.
        # DeleteRolePermissionsBoundary is deliberately not included.
        Sid    = "ManageBoundedRoles"
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy",
          "iam:AttachRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:DeleteRole",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = local.ack_role_arn_glob
        Condition = {
          StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.ack_tenant_boundary[0].arn }
        }
      },
      {
        Sid    = "ReadRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListRoleTags"
        ]
        Resource = local.ack_role_arn_glob
      },
      {
        # iam:PermissionsBoundary is not evaluated for PassRole, so a boundary condition here
        # would make it never match. The path restriction is enough: roles under this path can
        # only exist with the boundary (see CreateBoundedRoles).
        Sid      = "PassBoundedRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = local.ack_role_arn_glob
      }
    ]
  })
}

# Grants hub controller permission to assume the spoke role
resource "aws_iam_role_policy" "hub_ack_assume_spoke" {
  count = var.hub_ack_controller_role_arn != "" && var.spoke_account_id != "" ? 1 : 0
  name  = "assume-spoke-${var.spoke_account_id}"
  role  = split("/", var.hub_ack_controller_role_arn)[length(split("/", var.hub_ack_controller_role_arn)) - 1]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.ack_spoke[0].arn
    }]
  })
}

# ------------------------------------------------------------------------------
# 4. DISCOVERY CONTRACT (Phase 18.1): SSM Parameter Store Service Catalog
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "ack_cross_account_role" {
  count       = var.publish_ssm_parameters && var.hub_ack_controller_role_arn != "" ? 1 : 0
  name        = "/platform/${var.env}/${var.region}/ack/cross_account_role_arn"
  description = "Platform Discovery Contract: ACK Cross-Account Role ARN"
  type        = "String"
  value       = aws_iam_role.ack_spoke[0].arn

  tags = merge(
    {
      Service   = "governance-organization"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}
