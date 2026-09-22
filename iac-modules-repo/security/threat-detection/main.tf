# Threat detection (PLAN 4.4), applied in security-tooling (the delegated administrator for these services;
# delegation itself is granted by governance/organization's delegated_administrators, applied from the
# management account) and in every allowed region: GuardDuty, Security Hub, Inspector v2, Macie and,
# optionally, Detective. Each service auto-enables itself for every other account in the organization.
#
# The delegated administrator has to enable a service for ITSELF before it can auto-enable it for members
# (the org configuration resources depend on the account-level ones below).

data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region

  tags = merge({ Service = "security-threat-detection", ManagedBy = "Terragrunt-Wrapper" }, var.tags)

  securityhub_standard_arns = {
    fsbp   = "arn:${data.aws_partition.current.partition}:securityhub:${local.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
    cis-v3 = "arn:${data.aws_partition.current.partition}:securityhub:${local.region}::standards/cis-aws-foundations-benchmark/v/3.0.0"
  }

  # EKS_RUNTIME_MONITORING also needs the EKS_ADDON_MANAGEMENT sub-feature to let GuardDuty manage the runtime
  # agent add-on itself; every other feature has no sub-feature.
  guardduty_additional_configuration = {
    EKS_RUNTIME_MONITORING = "EKS_ADDON_MANAGEMENT"
  }
}

# ------------------------------------------------------------------------------
# GuardDuty
# ------------------------------------------------------------------------------
resource "aws_guardduty_detector" "this" {
  enable                       = true
  finding_publishing_frequency = var.guardduty_finding_publishing_frequency

  tags = local.tags
}

resource "aws_guardduty_organization_configuration" "this" {
  detector_id = aws_guardduty_detector.this.id

  auto_enable_organization_members = var.guardduty_auto_enable_organization_members
}

resource "aws_guardduty_organization_configuration_feature" "this" {
  for_each = toset(var.guardduty_features)

  detector_id = aws_guardduty_detector.this.id
  name        = each.value
  auto_enable = var.guardduty_auto_enable_organization_members

  dynamic "additional_configuration" {
    for_each = lookup(local.guardduty_additional_configuration, each.value, null) != null ? [local.guardduty_additional_configuration[each.value]] : []
    content {
      name        = additional_configuration.value
      auto_enable = var.guardduty_auto_enable_organization_members
    }
  }

  depends_on = [aws_guardduty_organization_configuration.this]
}

# ------------------------------------------------------------------------------
# Security Hub
# ------------------------------------------------------------------------------
resource "aws_securityhub_account" "this" {
  #checkov:skip=CKV2_AWS_78: "Default standards (auto-enabled by AWS) are replaced below with the two standards this platform actually subscribes to (FSBP, CIS v3); enabling both here too would just be turned off again"
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = var.securityhub_auto_enable_controls
}

resource "aws_securityhub_standards_subscription" "this" {
  for_each = { for s in var.securityhub_standards : s => local.securityhub_standard_arns[s] }

  standards_arn = each.value

  depends_on = [aws_securityhub_account.this]
}

resource "aws_securityhub_organization_configuration" "this" {
  auto_enable           = true
  auto_enable_standards = "NONE" # standards are chosen above (securityhub_standards), not AWS's defaults

  organization_configuration {
    configuration_type = "LOCAL" # each member manages its own subscription once auto-enabled; no central policy (out of scope here)
  }

  depends_on = [aws_securityhub_account.this]
}

resource "aws_securityhub_finding_aggregator" "this" {
  count = var.is_primary_region ? 1 : 0

  linking_mode = "ALL_REGIONS"

  depends_on = [aws_securityhub_account.this]
}

# ------------------------------------------------------------------------------
# Inspector v2
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_inspector2_enabler" "this" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = var.inspector2_resource_types
}

resource "aws_inspector2_organization_configuration" "this" {
  auto_enable {
    ec2    = contains(var.inspector2_resource_types, "EC2")
    ecr    = contains(var.inspector2_resource_types, "ECR")
    lambda = contains(var.inspector2_resource_types, "LAMBDA")
  }

  depends_on = [aws_inspector2_enabler.this]
}

# ------------------------------------------------------------------------------
# Macie
# ------------------------------------------------------------------------------
resource "aws_macie2_account" "this" {
  count = var.enable_macie ? 1 : 0

  finding_publishing_frequency = var.macie_finding_publishing_frequency
  status                       = "ENABLED"
}

resource "aws_macie2_organization_configuration" "this" {
  count = var.enable_macie ? 1 : 0

  auto_enable = true

  depends_on = [aws_macie2_account.this]
}

# ------------------------------------------------------------------------------
# Detective (optional)
# ------------------------------------------------------------------------------
resource "aws_detective_graph" "this" {
  count = var.enable_detective && var.is_primary_region ? 1 : 0

  tags = local.tags
}

resource "aws_detective_organization_configuration" "this" {
  count = var.enable_detective && var.is_primary_region ? 1 : 0

  graph_arn   = aws_detective_graph.this[0].graph_arn
  auto_enable = true
}
