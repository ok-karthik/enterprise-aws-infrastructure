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
  # Optional: once the platform-workload-boundary exists (PLAN 2.5), pass its ARN so that
  # PlatformEngineers can only create/modify roles that carry it.
  boundary_condition = var.permissions_boundary_arn != "" ? {
    Condition = { StringEquals = { "iam:PermissionsBoundary" = var.permissions_boundary_arn } }
  } : {}
}

# ------------------------------------------------------------------------------
# 1. Platform Engineer Permission Set (day-to-day, no standing admin)
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "platform_engineer" {
  count            = var.sso_instance_arn != "" ? 1 : 0
  name             = "${var.name_prefix}-PlatformEngineer"
  description      = "Power-user access for Platform and SRE engineers; IAM limited to role/platform/*. No standing administrator access."
  instance_arn     = var.sso_instance_arn
  session_duration = var.session_duration

  tags = merge(
    {
      Service = "identity-human-access"
      Role    = "PlatformEngineer"
    },
    var.tags
  )
}

resource "aws_ssoadmin_managed_policy_attachment" "platform_engineer_power_user" {
  count              = var.sso_instance_arn != "" ? 1 : 0
  instance_arn       = var.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
  permission_set_arn = aws_ssoadmin_permission_set.platform_engineer[0].arn
}

# PowerUserAccess blocks IAM (apart from service-linked roles). This adds back the IAM actions
# a platform engineer needs, and only for roles under the /platform/ path.
resource "aws_ssoadmin_permission_set_inline_policy" "platform_engineer_iam" {
  count              = var.sso_instance_arn != "" ? 1 : 0
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.platform_engineer[0].arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      merge({
        Sid    = "ManagePlatformRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
          "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:TagRole",
          "iam:UntagRole"
        ]
        Resource = "arn:aws:iam::*:role/platform/*"
      }, local.boundary_condition),
      {
        Sid    = "ReadAndPassPlatformRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListRoleTags",
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::*:role/platform/*"
      },
      {
        # Without this, "create a role under /platform/ and attach AdministratorAccess" would
        # be a way to get standing admin without the BreakGlassAdmin path.
        Sid      = "DenyAdminPolicyAttachment"
        Effect   = "Deny"
        Action   = ["iam:AttachRolePolicy", "iam:PutRolePolicy"]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "iam:PolicyARN" = [
              "arn:aws:iam::aws:policy/AdministratorAccess",
              "arn:aws:iam::aws:policy/IAMFullAccess"
            ]
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 1b. Break-glass Administrator Permission Set (short session, NOT assigned by default)
# ------------------------------------------------------------------------------
# This module only creates the permission set. It never creates account assignments, so nobody
# has it until it is granted deliberately (PLAN 3.3 wires that to just-in-time approval).
resource "aws_ssoadmin_permission_set" "break_glass" {
  count            = var.sso_instance_arn != "" ? 1 : 0
  name             = "${var.name_prefix}-BreakGlassAdmin"
  description      = "Emergency administrator access. 1-hour sessions. Not assigned by default; grant only through the break-glass procedure."
  instance_arn     = var.sso_instance_arn
  session_duration = var.break_glass_session_duration

  tags = merge(
    {
      Service = "identity-human-access"
      Role    = "BreakGlassAdmin"
    },
    var.tags
  )
}

resource "aws_ssoadmin_managed_policy_attachment" "break_glass_admin" {
  count              = var.sso_instance_arn != "" ? 1 : 0
  instance_arn       = var.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.break_glass[0].arn
}

# ------------------------------------------------------------------------------
# 2. Application Developer Permission Set
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "developer" {
  count            = var.sso_instance_arn != "" ? 1 : 0
  name             = "${var.name_prefix}-Developer"
  description      = "Scoped developer access for deploying and debugging microservices"
  instance_arn     = var.sso_instance_arn
  session_duration = var.session_duration

  tags = merge(
    {
      Service = "identity-human-access"
      Role    = "Developer"
    },
    var.tags
  )
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_view" {
  count              = var.sso_instance_arn != "" ? 1 : 0
  instance_arn       = var.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.developer[0].arn
}

# ------------------------------------------------------------------------------
# 3. Security & Compliance Auditor Permission Set
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "auditor" {
  count            = var.sso_instance_arn != "" ? 1 : 0
  name             = "${var.name_prefix}-AuditorReadOnly"
  description      = "Read-only security audit access for compliance and FinOps"
  instance_arn     = var.sso_instance_arn
  session_duration = var.session_duration

  tags = merge(
    {
      Service = "identity-human-access"
      Role    = "Auditor"
    },
    var.tags
  )
}

resource "aws_ssoadmin_managed_policy_attachment" "auditor_security" {
  count              = var.sso_instance_arn != "" ? 1 : 0
  instance_arn       = var.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
  permission_set_arn = aws_ssoadmin_permission_set.auditor[0].arn
}

# ------------------------------------------------------------------------------
# 4. EKS Access Entries & Cluster View Associations
# ------------------------------------------------------------------------------
resource "aws_eks_access_entry" "team" {
  for_each = var.cluster_name != "" ? var.team_access : {}

  cluster_name      = var.cluster_name
  principal_arn     = each.value.principal_arn
  kubernetes_groups = each.value.k8s_groups
  type              = "STANDARD"

  tags = merge(
    {
      Service = "identity-human-access"
    },
    var.tags
  )
}

resource "aws_eks_access_policy_association" "team_view" {
  for_each = var.cluster_name != "" ? var.team_access : {}

  cluster_name  = var.cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }
}
