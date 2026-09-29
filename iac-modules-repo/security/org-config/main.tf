# AWS Config organization-wide governance (PLAN 4.3):
# Applied in security-tooling (delegated administrator for Config).
# 1. Config recorder and delivery channel in every allowed region.
# 2. Multi-account multi-region aggregator in primary region.
# 3. Organization Conformance Packs (CIS AWS Foundations Benchmark, NIST 800-53 rev 5, SOC 2).

data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  region    = data.aws_region.current.region
  partition = data.aws_partition.current.partition

  tags = merge({
    Service   = "security-org-config"
    ManagedBy = "Terragrunt-Wrapper"
  }, var.tags)
}

# ------------------------------------------------------------------------------
# 1. IAM Role for Regional AWS Config Recorder
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  name               = "aws-config-role-${local.region}"
  description        = "Service role used by AWS Config recorder in ${local.region}"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "config" {
  #checkov:skip=CKV_AWS_274: "AWS Config service role requires managed AWS_ConfigRole policy for broad metadata inspection"
  role       = aws_iam_role.config.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

# ------------------------------------------------------------------------------
# 2. AWS Config Recorder & Delivery Channel (Per Region)
# ------------------------------------------------------------------------------
resource "aws_config_configuration_recorder" "this" {
  #checkov:skip=CKV2_AWS_48: "Global resource types are recorded exclusively in the primary region (var.is_primary_region) to avoid duplicate global recording events across regions"
  name     = "platform-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = var.is_primary_region
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "platform-config-delivery"
  s3_bucket_name = var.config_delivery_bucket_name

  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_delivery_frequency
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

# ------------------------------------------------------------------------------
# 3. Multi-Account Organization Aggregator (Primary Region in security-tooling)
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "aggregator_assume" {
  count = var.is_primary_region ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config_aggregator" {
  count = var.is_primary_region ? 1 : 0

  name               = "aws-config-org-aggregator-role"
  description        = "Service role for organization-wide Config aggregator"
  assume_role_policy = data.aws_iam_policy_document.aggregator_assume[0].json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  #checkov:skip=CKV_AWS_274: "Aggregator requires standard AWSConfigRoleForOrganizations managed policy"
  count = var.is_primary_region ? 1 : 0

  role       = aws_iam_role.config_aggregator[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "organization" {
  count = var.is_primary_region ? 1 : 0

  name = "organization-aggregator"

  organization_aggregation_source {
    all_regions = false
    regions     = var.allowed_regions
    role_arn    = aws_iam_role.config_aggregator[0].arn
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy_attachment.config_aggregator]
}

# ------------------------------------------------------------------------------
# 4. Organization Conformance Packs (Primary Region)
# ------------------------------------------------------------------------------
resource "aws_config_organization_conformance_pack" "cis" {
  count = var.is_primary_region && var.enable_cis_conformance_pack ? 1 : 0

  name              = "Operational-Best-Practices-for-CIS"
  template_s3_uri   = "s3://aws-configservice-conformance-packs-${local.region}/Operational-Best-Practices-for-CIS-AWS-Foundations-Benchmark-v1.4.yaml"
  excluded_accounts = var.excluded_accounts

  depends_on = [aws_config_configuration_recorder_status.this]
}

resource "aws_config_organization_conformance_pack" "nist" {
  count = var.is_primary_region && var.enable_nist_800_53_conformance_pack ? 1 : 0

  name              = "Operational-Best-Practices-for-NIST-800-53"
  template_s3_uri   = "s3://aws-configservice-conformance-packs-${local.region}/Operational-Best-Practices-for-NIST-800-53-rev-5.yaml"
  excluded_accounts = var.excluded_accounts

  depends_on = [aws_config_configuration_recorder_status.this]
}

resource "aws_config_organization_conformance_pack" "soc2" {
  count = var.is_primary_region && var.enable_soc2_conformance_pack ? 1 : 0

  name              = "Operational-Best-Practices-for-SOC2"
  template_s3_uri   = "s3://aws-configservice-conformance-packs-${local.region}/Operational-Best-Practices-for-AICPA-SOC2.yaml"
  excluded_accounts = var.excluded_accounts

  depends_on = [aws_config_configuration_recorder_status.this]
}
