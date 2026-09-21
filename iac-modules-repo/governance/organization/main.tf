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

resource "aws_organizations_policy" "deny_unapproved_regions" {
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

  tags       = local.tags
  depends_on = [aws_organizations_organization.this]
}

# Attach every guardrail to every OU in var.guardrail_target_ous. Static keys: policy IDs are only
# known after apply. SCPs never apply to the management account, whatever they are attached to.
locals {
  guardrail_policy_ids = {
    deny_leave_org          = aws_organizations_policy.deny_leave_org.id
    deny_disable_cloudtrail = aws_organizations_policy.deny_disable_cloudtrail.id
    deny_unapproved_regions = aws_organizations_policy.deny_unapproved_regions.id
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
