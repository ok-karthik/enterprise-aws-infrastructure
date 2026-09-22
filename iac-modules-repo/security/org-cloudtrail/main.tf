# Organization CloudTrail (PLAN 4.2), applied once in the management account: one multi-region trail that covers
# every account in the organization, delivering to the log-archive bucket built by security/log-archive. The two
# modules share a naming contract (bucket name, trail name) so neither has to read the other's state.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # Built from variables/data sources, not from the resource's own .arn attribute: the SNS topic policy and the
  # KMS key policy below both need the trail's ARN, and referencing aws_cloudtrail.org.arn there would make a
  # dependency cycle (the trail also references the topic and the log group that these policies protect).
  trail_arn = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${var.trail_name}"

  tags = merge({ Service = "security-org-cloudtrail", ManagedBy = "Terragrunt-Wrapper" }, var.tags)

  # A trail with any advanced_event_selector stops logging management events by the old implicit default, so when
  # data events are wanted an explicit "log management events too" selector is added alongside the data one.
  field_selectors_by_name = {
    ManagementEvents = [
      { field = "eventCategory", equals = ["Management"], starts_with = null },
    ]
    S3DataEventsForConfidentialBuckets = [
      { field = "eventCategory", equals = ["Data"], starts_with = null },
      { field = "resources.type", equals = ["AWS::S3::Object"], starts_with = null },
      { field = "resources.ARN", equals = null, starts_with = [for arn in var.confidential_s3_bucket_arns : "${arn}/"] },
    ]
  }
  advanced_event_selector_names = length(var.confidential_s3_bucket_arns) > 0 ? ["ManagementEvents", "S3DataEventsForConfidentialBuckets"] : []
}

# ------------------------------------------------------------------------------
# CloudWatch Logs delivery: the audit trail is also readable in real time (metric filters, alarms),
# not only as S3 objects in another account. A small key local to this account, separate from the
# log-archive key (CloudWatch Logs needs a key in its own account and region).
# ------------------------------------------------------------------------------
resource "aws_kms_key" "trail_support" {
  description             = "Encrypts the org trail's CloudWatch Logs group and SNS notification topic (management account)"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIamPolicies"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # Standard CloudWatch Logs KMS grant pattern: scoped to log groups in this account and region.
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = { ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:${local.partition}:logs:${local.region}:${local.account_id}:*" } }
      },
      {
        Sid       = "AllowCloudTrailToPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
    ]
  })

  tags = local.tags
}

resource "aws_kms_alias" "trail_support" {
  name          = "alias/${var.trail_name}-support"
  target_key_id = aws_kms_key.trail_support.key_id
}

resource "aws_cloudwatch_log_group" "org_trail" {
  name              = "/aws/cloudtrail/${var.trail_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.trail_support.arn

  tags = local.tags
}

resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  name = "${var.trail_name}-cloudwatch-delivery"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudTrailToAssume"
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch" {
  name = "deliver-to-log-group"
  role = aws_iam_role.cloudtrail_to_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowLogDelivery"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.org_trail.arn}:*"
    }]
  })
}

# ------------------------------------------------------------------------------
# SNS notification of each log delivery (CKV_AWS_252): not an alert channel (that is
# security/break-glass-alerts and PLAN 4.5's EventBridge rules on the trail's own events), just
# CloudTrail's built-in "a new log file was delivered" notice.
# ------------------------------------------------------------------------------
resource "aws_sns_topic" "trail_notifications" {
  name              = "${var.trail_name}-notifications"
  kms_master_key_id = aws_kms_key.trail_support.arn

  tags = local.tags
}

resource "aws_sns_topic_policy" "trail_notifications" {
  arn = aws_sns_topic.trail_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudTrailToPublish"
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.trail_notifications.arn
      Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
    }]
  })
}

resource "aws_cloudtrail" "org" {
  name           = var.trail_name
  s3_bucket_name = var.log_archive_bucket_name
  s3_key_prefix  = var.s3_key_prefix != "" ? var.s3_key_prefix : null
  kms_key_id     = var.kms_key_arn
  sns_topic_name = aws_sns_topic.trail_notifications.name

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.org_trail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_cloudwatch.arn

  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true

  dynamic "advanced_event_selector" {
    for_each = local.advanced_event_selector_names
    content {
      name = advanced_event_selector.value

      dynamic "field_selector" {
        for_each = local.field_selectors_by_name[advanced_event_selector.value]
        content {
          field       = field_selector.value.field
          equals      = field_selector.value.equals
          starts_with = field_selector.value.starts_with
        }
      }
    }
  }

  tags = local.tags
}

resource "aws_cloudtrail_event_data_store" "org" {
  count = var.enable_cloudtrail_lake ? 1 : 0

  name                           = "${var.trail_name}-lake"
  multi_region_enabled           = true
  organization_enabled           = true
  retention_period               = var.cloudtrail_lake_retention_days
  termination_protection_enabled = true
  kms_key_id                     = var.kms_key_arn

  tags = local.tags
}
