# Account baseline, applied to EVERY account (management, workloads, ...). The state bucket, the OIDC
# provider and the CI roles are NOT here: they come from the Day-0 bootstrap (CloudFormation / StackSets),
# because this module needs them before it can run.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  boundary_name = "platform-workload-boundary"
  boundary_arn  = "arn:${local.partition}:iam::${local.account_id}:policy/${local.boundary_name}"

  tags = merge(
    {
      Service   = "governance-account-baseline"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

# ------------------------------------------------------------------------------
# 1. Account alias and IAM password policy
# ------------------------------------------------------------------------------
resource "aws_iam_account_alias" "this" {
  count         = var.account_alias != "" ? 1 : 0
  account_alias = var.account_alias
}

resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = var.password_policy_min_length
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
  hard_expiry                    = false
}

# ------------------------------------------------------------------------------
# 2. Account-wide safe defaults
# ------------------------------------------------------------------------------
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# IMDSv2 as the default for new instances in this region. The hop limit is left to each workload
# (EKS nodes set 1 in the eks module).
resource "aws_ec2_instance_metadata_defaults" "this" {
  http_tokens   = "required"
  http_endpoint = "enabled"
}

# ------------------------------------------------------------------------------
# 3. KMS keys per data class (rotation on)
# ------------------------------------------------------------------------------
locals {
  # Standard key policy: the account root delegates key use to IAM (the AWS default), so the key stays manageable.
  kms_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableIamPolicies"
      Effect    = "Allow"
      Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

resource "aws_kms_key" "general" {
  description             = "Platform key for general (internal) data in this account"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = local.kms_policy

  tags = merge(local.tags, { DataClass = "general" })
}

resource "aws_kms_alias" "general" {
  name          = "alias/platform-general"
  target_key_id = aws_kms_key.general.key_id
}

resource "aws_kms_key" "confidential" {
  description             = "Platform key for confidential data in this account"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = local.kms_policy

  tags = merge(local.tags, { DataClass = "confidential" })
}

resource "aws_kms_alias" "confidential" {
  name          = "alias/platform-confidential"
  target_key_id = aws_kms_key.confidential.key_id
}

# ------------------------------------------------------------------------------
# 4. platform-workload-boundary: every role that Terraform, ACK or tenants create must carry it
# ------------------------------------------------------------------------------
locals {
  # A permissions boundary must Allow everything and then Deny specific actions: it only ever narrows a role.
  workload_boundary_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowEverythingElse"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      },
      {
        # A role created under this boundary can only create roles that carry the same boundary, so
        # the boundary cannot be shed by creating a new role.
        Sid       = "DenyRoleWithoutThisBoundary"
        Effect    = "Deny"
        Action    = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
        Resource  = "*"
        Condition = { StringNotEquals = { "iam:PermissionsBoundary" = local.boundary_arn } }
      },
      {
        Sid      = "DenyBoundaryRemoval"
        Effect   = "Deny"
        Action   = ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary", "iam:PutUserPermissionsBoundary"]
        Resource = "*"
      },
      {
        Sid      = "DenyEditingThisBoundary"
        Effect   = "Deny"
        Action   = ["iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion"]
        Resource = local.boundary_arn
      },
      {
        Sid      = "DenyHumanIdentitiesAndKeys"
        Effect   = "Deny"
        Action   = ["iam:CreateUser", "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "iam:CreateAccessKey"]
        Resource = "*"
      },
      {
        Sid    = "DenyEditingPlatformRoles"
        Effect = "Deny"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DeleteRole",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:UpdateAssumeRolePolicy",
          "iam:UpdateRole",
        ]
        Resource = [
          "arn:${local.partition}:iam::${local.account_id}:role/platform-*",
          "arn:${local.partition}:iam::${local.account_id}:role/terraform-*",
          "arn:${local.partition}:iam::${local.account_id}:role/github-actions-*",
          "arn:${local.partition}:iam::${local.account_id}:role/OrganizationAccountAccessRole",
        ]
      },
      {
        Sid    = "DenySecurityServiceTampering"
        Effect = "Deny"
        Action = [
          "access-analyzer:DeleteAnalyzer",
          "cloudtrail:DeleteTrail",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder",
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:StopMonitoringMembers",
          "macie2:DisableMacie",
          "securityhub:BatchDisableStandards",
          "securityhub:DisableSecurityHub",
          "securityhub:DisassociateFromAdministratorAccount",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyLoweringAccountDefaults"
        Effect = "Deny"
        Action = [
          "ec2:DisableEbsEncryptionByDefault",
          "ec2:ModifyInstanceMetadataDefaults",
          "iam:DeleteAccountPasswordPolicy",
          "iam:UpdateAccountPasswordPolicy",
          "s3:PutAccountPublicAccessBlock",
        ]
        Resource = "*"
      },
      {
        Sid      = "DenyOrganizationAndIdentity"
        Effect   = "Deny"
        Action   = ["account:*", "identitystore:*", "organizations:*", "sso-directory:*", "sso:*"]
        Resource = "*"
      },
    ]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = local.boundary_name
  description = "Permissions boundary for every role created by Terraform, ACK or tenants in this account"
  policy      = jsonencode(local.workload_boundary_policy)

  tags = local.tags
}

# ------------------------------------------------------------------------------
# 5. DISCOVERY CONTRACT (account dimension, PLAN 2.7): who and where this account is, and its keys
# ------------------------------------------------------------------------------
locals {
  discovery_parameters = var.publish_ssm_parameters ? {
    "account/id"                = local.account_id
    "account/ou"                = var.ou
    "kms/general_key_arn"       = aws_kms_key.general.arn
    "kms/confidential_key_arn"  = aws_kms_key.confidential.arn
    "iam/workload_boundary_arn" = aws_iam_policy.workload_boundary.arn
  } : {}
}

resource "aws_ssm_parameter" "discovery" {
  #checkov:skip=CKV2_AWS_34: "Platform discovery catalog parameter contains non-sensitive metadata"
  for_each = local.discovery_parameters

  name        = "/platform/${var.env}/${var.region}/${each.key}"
  description = "Platform Discovery Contract: ${each.key} for ${var.env} in ${var.region}"
  type        = "String"
  value       = each.value

  tags = local.tags
}
