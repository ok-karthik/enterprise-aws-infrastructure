# IAM Identity Center for humans: the permission-set catalog, the groups, and the assignments
# "OU -> group -> permission set" expanded to accounts with the account registry. Applied from the
# management account. The IdP itself (Okta / Entra ID / Google) and SCIM are set up by hand, see
# docs/IDENTITY.md. Identity Center must already be enabled (it is per organization and region).

data "aws_ssoadmin_instances" "this" {}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  aws_managed = "arn:aws:iam::aws:policy"

  # The catalog. Sessions: 1 hour for the elevated sets, 8 hours for the rest (var.session_durations).
  permission_sets = {
    ReadOnly = {
      description      = "Read-only access to everything (ReadOnlyAccess)"
      managed_policies = ["${local.aws_managed}/ReadOnlyAccess"]
    }
    Developer = {
      description      = "Developers in NonProd and Sandbox: the platform-developer policy, capped by platform-workload-boundary. In Prod use ReadOnly."
      managed_policies = []
    }
    PlatformEngineer = {
      description      = "Platform and SRE engineers: PowerUserAccess plus IAM limited to role/platform/*. No standing administrator access. In Prod only just in time."
      managed_policies = ["${local.aws_managed}/PowerUserAccess"]
    }
    SecurityAudit = {
      description      = "Read-only security audit and compliance access (SecurityAudit + ViewOnlyAccess)"
      managed_policies = ["${local.aws_managed}/SecurityAudit", "${local.aws_managed}/job-function/ViewOnlyAccess"]
    }
    Billing = {
      description      = "Billing and cost access (Billing)"
      managed_policies = ["${local.aws_managed}/job-function/Billing"]
    }
    BreakGlassAdmin = {
      description      = "Emergency administrator access. 1-hour sessions. Never assigned statically: granted just in time (docs/BREAK_GLASS.md)."
      managed_policies = ["${local.aws_managed}/AdministratorAccess"]
    }
  }

  managed_policy_attachments = merge([
    for name, ps in local.permission_sets : {
      for arn in ps.managed_policies : "${name}/${basename(arn)}" => { permission_set = name, arn = arn }
    }
  ]...)

  tags = merge({ Service = "identity-center", ManagedBy = "Terragrunt-Wrapper" }, var.tags)
}

# ------------------------------------------------------------------------------
# 1. Permission-set catalog
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "this" {
  for_each = local.permission_sets

  name             = each.key
  description      = each.value.description
  instance_arn     = local.instance_arn
  session_duration = var.session_durations[each.key]

  tags = merge(local.tags, { Role = each.key })
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.managed_policy_attachments

  instance_arn       = local.instance_arn
  managed_policy_arn = each.value.arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
}

# Developer: a customer-managed policy and a permissions boundary, both attached BY NAME. They must
# exist in every account the set is assigned to: governance/account-baseline creates them.
resource "aws_ssoadmin_customer_managed_policy_attachment" "developer" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["Developer"].arn

  customer_managed_policy_reference {
    name = var.developer_policy_name
    path = "/"
  }
}

resource "aws_ssoadmin_permissions_boundary_attachment" "developer" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["Developer"].arn

  permissions_boundary {
    customer_managed_policy_reference {
      name = var.workload_boundary_name
      path = "/"
    }
  }
}

# PowerUserAccess blocks IAM. This adds back the IAM a platform engineer needs, only for roles under
# the /platform/ path, and only for roles that carry the workload boundary.
resource "aws_ssoadmin_permission_set_inline_policy" "platform_engineer" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["PlatformEngineer"].arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
          "iam:UntagRole",
        ]
        Resource  = "arn:aws:iam::*:role/platform/*"
        Condition = { ArnLike = { "iam:PermissionsBoundary" = "arn:aws:iam::*:policy/${var.workload_boundary_name}" } }
      },
      {
        Sid      = "ReadAndPassPlatformRoles"
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListRoleTags", "iam:PassRole"]
        Resource = "arn:aws:iam::*:role/platform/*"
      },
      {
        # Without this, "create a role under /platform/ and attach AdministratorAccess" would be a
        # way to get standing admin without the just-in-time path.
        Sid      = "DenyAdminPolicyAttachment"
        Effect   = "Deny"
        Action   = ["iam:AttachRolePolicy", "iam:PutRolePolicy"]
        Resource = "*"
        Condition = {
          ArnEquals = { "iam:PolicyARN" = ["${local.aws_managed}/AdministratorAccess", "${local.aws_managed}/IAMFullAccess"] }
        }
      },
    ]
  })
}

# ------------------------------------------------------------------------------
# 2. Attributes for access control (ABAC): team and cost_center become session tags
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_instance_access_control_attributes" "this" {
  count        = length(var.abac_attributes) > 0 ? 1 : 0
  instance_arn = local.instance_arn

  dynamic "attribute" {
    for_each = var.abac_attributes

    content {
      key = attribute.key
      value {
        source = [attribute.value]
      }
    }
  }
}

# ------------------------------------------------------------------------------
# 3. Groups: created (no external IdP) or looked up (SCIM-synced)
# ------------------------------------------------------------------------------
resource "aws_identitystore_group" "this" {
  for_each = var.manage_groups ? toset(var.groups) : toset([])

  identity_store_id = local.identity_store_id
  display_name      = each.value
  description       = "Managed by Terraform (identity-center)"
}

data "aws_identitystore_group" "scim" {
  for_each = var.manage_groups ? toset([]) : toset(var.groups)

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.value
    }
  }
}

locals {
  group_ids = var.manage_groups ? { for g, r in aws_identitystore_group.this : g => r.group_id } : { for g, r in data.aws_identitystore_group.scim : g => r.group_id }

  # OU => group => sets, expanded to (account, group, set).
  assignment_list = flatten([
    for ou, groups in var.assignments : [
      for group, sets in groups : [
        for set in sets : [
          for name, account in var.accounts : {
            key        = "${name}/${group}/${set}"
            account_id = account.id
            group      = group
            set        = set
          } if account.ou == ou
        ]
      ]
    ]
  ])
}

# ------------------------------------------------------------------------------
# 4. Account assignments
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_account_assignment" "this" {
  for_each = { for a in local.assignment_list : a.key => a }

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.set].arn

  principal_id   = local.group_ids[each.value.group]
  principal_type = "GROUP"

  target_id   = each.value.account_id
  target_type = "AWS_ACCOUNT"
}
