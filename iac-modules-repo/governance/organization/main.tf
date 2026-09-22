# AWS Organization foundation: the organization itself (service access + policy types), the OU
# tree, and the baseline SCP guardrails. Applied from the management account only, by the owner.
#
# The organization already exists (bootstrap.sh creates it), so it must be IMPORTED before the
# first apply, see README. Service access principals and policy types are AUTHORITATIVE: anything
# enabled by hand that is not in the lists below gets disabled on apply. Read the plan first.

locals {
  top_level_ous = { for name, ou in var.organizational_units : name => ou if ou.parent == null }
  child_ous     = { for name, ou in var.organizational_units : name => ou if ou.parent != null }

  tags = merge(
    {
      Service   = "governance-organization"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

# ------------------------------------------------------------------------------
# 1. Organization
# ------------------------------------------------------------------------------
resource "aws_organizations_organization" "this" {
  feature_set                   = "ALL"
  aws_service_access_principals = var.aws_service_access_principals
  enabled_policy_types          = var.enabled_policy_types

  lifecycle {
    # Deleting the organization would take every member account with it.
    prevent_destroy = true
  }
}

# ------------------------------------------------------------------------------
# 1b. Centralized root access management (PLAN 3.5)
# ------------------------------------------------------------------------------
# Removes the need for root credentials in member accounts: they can be deleted, and a privileged
# root task is done from the management account with sts:AssumeRoot (docs/ROOT_ACCESS.md). Needs
# trusted access for iam.amazonaws.com (in the default aws_service_access_principals).
resource "aws_iam_organizations_features" "this" {
  count = var.enable_centralized_root_access ? 1 : 0

  enabled_features = ["RootCredentialsManagement", "RootSessions"]

  lifecycle {
    precondition {
      condition     = contains(var.aws_service_access_principals, "iam.amazonaws.com")
      error_message = "Centralized root access needs trusted access for iam.amazonaws.com in aws_service_access_principals."
    }
  }

  depends_on = [aws_organizations_organization.this]
}

# ------------------------------------------------------------------------------
# 1c. Delegated administrators (PLAN 3.6 and 4.x): a service is administered from another account
# ------------------------------------------------------------------------------
# The service must have trusted access (aws_service_access_principals). The management account cannot
# be a delegated administrator of itself.
resource "aws_organizations_delegated_administrator" "this" {
  for_each = var.delegated_administrators

  account_id        = each.value
  service_principal = each.key

  depends_on = [aws_organizations_organization.this]
}

# ------------------------------------------------------------------------------
# 2. Organizational units (two levels: top-level OUs, and OUs under a top-level OU)
# ------------------------------------------------------------------------------
resource "aws_organizations_organizational_unit" "top" {
  for_each = local.top_level_ous

  name      = each.key
  parent_id = aws_organizations_organization.this.roots[0].id
  tags      = local.tags
}

resource "aws_organizations_organizational_unit" "child" {
  for_each = local.child_ous

  name      = each.key
  parent_id = aws_organizations_organizational_unit.top[each.value.parent].id
  tags      = local.tags
}

locals {
  organizational_unit_ids = merge(
    { for name, ou in aws_organizations_organizational_unit.top : name => ou.id },
    { for name, ou in aws_organizations_organizational_unit.child : name => ou.id },
  )
}

# ------------------------------------------------------------------------------
# 3. Service Control Policies (SCPs)
# ------------------------------------------------------------------------------
resource "aws_organizations_policy" "deny_leave_org" {
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

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy" "deny_disable_cloudtrail" {
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

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
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

# One region policy PER OU (PLAN 4.6), replacing the single org-wide list this module used to attach to
# guardrail_target_ous. Each OU only gets its own policy, attached only to itself: a mistake in one OU's list
# can never widen or narrow another OU's regions. An OU with no entry (or an empty list) in
# var.allowed_regions_by_ou gets no region policy at all (nothing is denied on its behalf here).
resource "aws_organizations_policy" "deny_unapproved_regions" {
  for_each = { for ou, regions in var.allowed_regions_by_ou : ou => regions if length(regions) > 0 }

  name        = "deny-unapproved-regions-${lower(replace(each.key, " ", "-"))}"
  description = "Data residency control for the ${each.key} OU: deny requests to any region outside ${jsonencode(each.value)}, except global services"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyUnapprovedRegions"
      Effect    = "Deny"
      NotAction = local.region_exempt_actions
      Resource  = "*"
      Condition = {
        StringNotEquals = { "aws:RequestedRegion" = each.value }
      }
    }]
  })

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy_attachment" "deny_unapproved_regions" {
  for_each = aws_organizations_policy.deny_unapproved_regions

  policy_id = each.value.id
  target_id = local.organizational_unit_ids[each.key]
}

# ------------------------------------------------------------------------------
# 3b. Additional guardrails (PLAN 4.6), attached the same way as the ones above: to every OU in
# var.guardrail_target_ous (default: Policy-Staging only). Two of them (deny_iam_user_creation and
# protect_platform_resources) exempt the StackSets service-linked role and BreakGlassAdmin, both matched by
# their assumed-role ARN pattern, not by a Principal element: SCPs do not support Principal/NotPrincipal at all.
# ------------------------------------------------------------------------------
locals {
  exception_principal_arns = [
    "arn:*:sts::*:assumed-role/AWSServiceRoleForCloudFormationStackSetsOrgMember/*",
    var.break_glass_role_arn_pattern,
  ]
}

resource "aws_organizations_policy" "deny_root_user_actions" {
  name        = "deny-root-user-actions"
  description = "Deny every action taken as the account's literal root user (not a break-glass sts:AssumeRoot session, which has a different principal ARN shape, see docs/ROOT_ACCESS.md)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyRootUser"
      Effect    = "Deny"
      Action    = "*"
      Resource  = "*"
      Condition = { StringLike = { "aws:PrincipalArn" = "arn:*:iam::*:root" } }
    }]
  })

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy" "deny_disable_detection_services" {
  name        = "deny-disable-detection-services"
  description = "Deny disabling or disassociating from Config, GuardDuty, Security Hub, Access Analyzer or Macie (CloudTrail has its own policy above). Same action list as account-baseline's DenySecurityServiceTampering, so both layers agree."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyDisableDetectionServices"
      Effect = "Deny"
      Action = [
        "access-analyzer:DeleteAnalyzer",
        "config:DeleteConfigurationRecorder",
        "config:DeleteDeliveryChannel",
        "config:StopConfigurationRecorder",
        "guardduty:DeleteDetector",
        "guardduty:DisassociateFromMasterAccount",
        "guardduty:DisassociateMembers",
        "guardduty:StopMonitoringMembers",
        "macie2:DisableMacie",
        "macie2:DisassociateFromAdministratorAccount",
        "macie2:DisassociateFromMasterAccount",
        "securityhub:BatchDisableStandards",
        "securityhub:DisableSecurityHub",
        "securityhub:DisassociateFromAdministratorAccount",
        "securityhub:DisassociateFromMasterAccount",
        "securityhub:DisassociateMembers",
      ]
      Resource = "*"
    }]
  })

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy" "deny_iam_user_creation" {
  name        = "deny-iam-user-creation"
  description = "Deny creating IAM users, login profiles or access keys, except from a break-glass session (docs/ROOT_ACCESS.md's root-recovery tasks are a separate, root-only path and are not affected by this)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyIamUserAndKeyCreationExceptBreakGlass"
      Effect    = "Deny"
      Action    = ["iam:CreateUser", "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "iam:CreateAccessKey"]
      Resource  = "*"
      Condition = { StringNotLike = { "aws:PrincipalArn" = [var.break_glass_role_arn_pattern] } }
    }]
  })

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy" "protect_platform_resources" {
  name        = "protect-platform-resources"
  description = "Deny changes to platform-*/github-actions-* IAM roles, the GitHub OIDC provider, and tg-state-* state buckets, except from the StackSets service-linked role (member account bootstrap) or a break-glass session"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ProtectPlatformIamRoles"
        Effect = "Deny"
        Action = [
          "iam:AttachRolePolicy", "iam:DeleteRole", "iam:DeleteRolePolicy", "iam:DetachRolePolicy",
          "iam:PutRolePolicy", "iam:PutRolePermissionsBoundary", "iam:DeleteRolePermissionsBoundary",
          "iam:UpdateAssumeRolePolicy", "iam:UpdateRole",
        ]
        Resource = [
          "arn:*:iam::*:role/platform-*",
          "arn:*:iam::*:role/github-actions-*",
        ]
        Condition = { StringNotLike = { "aws:PrincipalArn" = local.exception_principal_arns } }
      },
      {
        Sid    = "ProtectGitHubOidcProvider"
        Effect = "Deny"
        Action = [
          "iam:DeleteOpenIDConnectProvider", "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider", "iam:RemoveClientIDFromOpenIDConnectProvider",
        ]
        Resource  = "arn:*:iam::*:oidc-provider/token.actions.githubusercontent.com"
        Condition = { StringNotLike = { "aws:PrincipalArn" = local.exception_principal_arns } }
      },
      {
        Sid    = "ProtectTerraformStateBuckets"
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket", "s3:DeleteBucketPolicy", "s3:PutBucketPolicy", "s3:PutBucketAcl",
          "s3:PutBucketVersioning", "s3:PutBucketPublicAccessBlock", "s3:PutEncryptionConfiguration",
        ]
        Resource  = "arn:*:s3:::tg-state-*"
        Condition = { StringNotLike = { "aws:PrincipalArn" = local.exception_principal_arns } }
      },
    ]
  })

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy" "require_imdsv2" {
  name        = "require-imdsv2"
  description = <<-EOT
    Deny launching an EC2 instance that does not require IMDSv2. Known compatibility risk before widening past
    Policy-Staging: iac-modules-repo/compute/eks's node groups must set metadata_http_tokens = "required" too,
    or node launches would start failing in whatever OU this is attached to.
  EOT
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "RequireImdsv2OnRunInstances"
      Effect    = "Deny"
      Action    = "ec2:RunInstances"
      Resource  = "arn:*:ec2:*:*:instance/*"
      Condition = { StringNotEquals = { "ec2:MetadataHttpTokens" = "required" } }
    }]
  })

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy" "deny_role_creation_without_boundary" {
  name        = "deny-role-creation-without-boundary"
  description = <<-EOT
    Deny creating an IAM role that does not carry the platform-workload-boundary permissions boundary (the
    same condition account-baseline's own workload boundary already enforces for roles created under it,
    see DenyRoleWithoutThisBoundary in iac-modules-repo/governance/account-baseline). This SCP is the backstop
    for identities that are NOT under that boundary at all. Known gap, same one the account-baseline version
    has: a CreateRole call that omits iam:PermissionsBoundary entirely does not match StringNotEquals, so it
    is not denied by this condition alone; account-baseline's Developer policy is what actually requires the
    boundary to be set for the identities it applies to.
  EOT
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyRoleCreationWithoutBoundary"
      Effect   = "Deny"
      Action   = "iam:CreateRole"
      Resource = "*"
      Condition = {
        StringNotEquals = { "iam:PermissionsBoundary" = "arn:*:iam::*:policy/platform-workload-boundary" }
      }
    }]
  })

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

# Sandbox: opt-in (default off). The Sandbox OU is the owner's free-experimentation account (learning-plan
# labs); this only takes effect once enable_sandbox_guardrails is turned on deliberately.
resource "aws_organizations_policy" "sandbox_guardrails" {
  count = var.enable_sandbox_guardrails ? 1 : 0

  name        = "sandbox-guardrails"
  description = "Sandbox only: deny large instance families (8xlarge and up, and bare metal) and Reserved Instance / Savings Plan purchases"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyLargeInstanceFamilies"
        Effect   = "Deny"
        Action   = "ec2:RunInstances"
        Resource = "arn:*:ec2:*:*:instance/*"
        Condition = {
          StringLike = {
            "ec2:InstanceType" = ["*.8xlarge", "*.9xlarge", "*.10xlarge", "*.12xlarge", "*.16xlarge", "*.18xlarge", "*.24xlarge", "*.32xlarge", "*.metal", "*.metal-*"]
          }
        }
      },
      {
        Sid      = "DenyReservedInstanceAndSavingsPlanPurchases"
        Effect   = "Deny"
        Action   = ["ec2:PurchaseReservedInstancesOffering", "savingsplans:CreateSavingsPlan"]
        Resource = "*"
      },
    ]
  })

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy_attachment" "sandbox_guardrails" {
  count = var.enable_sandbox_guardrails ? 1 : 0

  policy_id = aws_organizations_policy.sandbox_guardrails[0].id
  target_id = local.organizational_unit_ids["Sandbox"]
}

# Suspended: deny everything. Safe by construction: this OU starts empty (no account in _config/accounts.hcl
# is in it today), so it has zero blast radius until an account is actually moved there to be wound down.
resource "aws_organizations_policy" "suspended_deny_all" {
  count = var.enable_suspended_deny_all ? 1 : 0

  name        = "suspended-deny-all"
  description = "Suspended OU: deny every action. An account is moved here only when it is being wound down."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyEverything"
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
    }]
  })

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy_attachment" "suspended_deny_all" {
  count = var.enable_suspended_deny_all ? 1 : 0

  policy_id = aws_organizations_policy.suspended_deny_all[0].id
  target_id = local.organizational_unit_ids["Suspended"]
}

# Attach every generic guardrail to every OU in var.guardrail_target_ous. Static keys: policy IDs are only
# known after apply. SCPs never apply to the management account, whatever they are attached to.
locals {
  guardrail_policy_ids = {
    deny_leave_org                      = aws_organizations_policy.deny_leave_org.id
    deny_disable_cloudtrail             = aws_organizations_policy.deny_disable_cloudtrail.id
    deny_root_user_actions              = aws_organizations_policy.deny_root_user_actions.id
    deny_disable_detection_services     = aws_organizations_policy.deny_disable_detection_services.id
    deny_iam_user_creation              = aws_organizations_policy.deny_iam_user_creation.id
    protect_platform_resources          = aws_organizations_policy.protect_platform_resources.id
    require_imdsv2                      = aws_organizations_policy.require_imdsv2.id
    deny_role_creation_without_boundary = aws_organizations_policy.deny_role_creation_without_boundary.id
  }

  guardrail_attachments = {
    for pair in setproduct(keys(local.guardrail_policy_ids), var.guardrail_target_ous) :
    "${pair[0]}/${pair[1]}" => { policy = pair[0], ou = pair[1] }
  }
}

resource "aws_organizations_policy_attachment" "guardrails" {
  for_each = local.guardrail_attachments

  policy_id = local.guardrail_policy_ids[each.value.policy]
  target_id = local.organizational_unit_ids[each.value.ou]
}
