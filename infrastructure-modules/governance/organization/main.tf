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

resource "aws_organizations_policy" "deny_outside_eu_central_1" {
  count       = var.root_id != "" ? 1 : 0
  name        = "deny-region-outside-eu-central-1"
  description = "Data residency control restricting operations outside eu-central-1 except global services"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyOutsideEuCentral1"
      Effect = "Deny"
      NotAction = [
        "iam:*",
        "organizations:*",
        "route53:*",
        "cloudfront:*",
        "support:*",
        "sts:*"
      ]
      Resource = "*"
      Condition = {
        StringNotEquals = { "aws:RequestedRegion" = "eu-central-1" }
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
  for_each = var.root_id != "" ? toset([
    aws_organizations_policy.deny_leave_org[0].id,
    aws_organizations_policy.deny_disable_cloudtrail[0].id,
    aws_organizations_policy.deny_outside_eu_central_1[0].id
  ]) : []

  policy_id = each.value
  target_id = aws_organizations_organizational_unit.production[0].id
}

resource "aws_organizations_policy_attachment" "non_production_guardrails" {
  for_each = var.root_id != "" ? toset([
    aws_organizations_policy.deny_leave_org[0].id,
    aws_organizations_policy.deny_disable_cloudtrail[0].id,
    aws_organizations_policy.deny_outside_eu_central_1[0].id
  ]) : []

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

resource "aws_iam_role_policy_attachment" "ack_spoke_s3" {
  count      = var.hub_ack_controller_role_arn != "" ? 1 : 0
  role       = aws_iam_role.ack_spoke[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "ack_spoke_iam" {
  count      = var.hub_ack_controller_role_arn != "" ? 1 : 0
  role       = aws_iam_role.ack_spoke[0].name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
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
