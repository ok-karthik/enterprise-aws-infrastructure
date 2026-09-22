# Central log archive (PLAN 4.1), applied in the log-archive account: one Object Lock bucket per log type plus one KMS key.
# Object Lock in COMPLIANCE mode means nobody, not even the account root, can delete a log before its retention ends.
# Buckets accept writes only from the AWS services that deliver that log type, and only for this organization
# (aws:SourceOrgID). The conditions are the documented delivery patterns; whether each service accepts them can only
# be proven by a real delivery (README, "Not verified offline").

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  home       = var.trail_home_region != "" ? var.trail_home_region : local.region
  trail_arn  = "arn:${local.partition}:cloudtrail:${local.home}:${var.management_account_id}:trail/${var.trail_name}"

  tags = merge({ Service = "security-log-archive", ManagedBy = "Terragrunt-Wrapper" }, var.tags)

  # Log types that S3 can encrypt with a customer-managed key. ALB access logs and S3 server access logs only
  # support SSE-S3 (AES256), so those two buckets use it.
  kms_types = ["cloudtrail", "config", "vpc_flow_logs", "waf", "cloudfront_access"]

  buckets = {
    for t in var.enabled_log_types : t => {
      name      = t == "waf" ? "aws-waf-logs-${var.name_prefix}-${local.account_id}-${local.region}" : "${var.name_prefix}-${replace(t, "_", "-")}-${local.account_id}-${local.region}"
      retention = lookup(var.retention_days, t, 90)
      kms       = contains(local.kms_types, t)
    }
  }

  # ----------------------------------------------------------------------------
  # Bucket policy statements per log type. `arn` is built from the name, not from the resource, so the
  # policy can be built before the bucket exists.
  # ----------------------------------------------------------------------------
  org_condition = { StringEquals = { "aws:SourceOrgID" = var.organization_id } }
  acl_condition = { StringEquals = { "aws:SourceOrgID" = var.organization_id, "s3:x-amz-acl" = "bucket-owner-full-control" } }

  allow_statements = {
    cloudtrail = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = "arn:${local.partition}:s3:::%BUCKET%"
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource = [
          "arn:${local.partition}:s3:::%BUCKET%/AWSLogs/${var.management_account_id}/*",
          "arn:${local.partition}:s3:::%BUCKET%/AWSLogs/${var.organization_id}/*",
        ]
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn, "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
    ]
    config = [
      {
        Sid       = "ConfigAclCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = "arn:${local.partition}:s3:::%BUCKET%"
        Condition = local.org_condition
      },
      {
        Sid       = "ConfigWrite"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:${local.partition}:s3:::%BUCKET%/AWSLogs/*/Config/*"
        Condition = local.acl_condition
      },
    ]
    vpc_flow_logs = [
      {
        Sid       = "LogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = "arn:${local.partition}:s3:::%BUCKET%"
        Condition = local.org_condition
      },
      {
        Sid       = "LogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:${local.partition}:s3:::%BUCKET%/AWSLogs/*"
        Condition = local.acl_condition
      },
    ]
    waf = [
      {
        Sid       = "LogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = "arn:${local.partition}:s3:::%BUCKET%"
        Condition = local.org_condition
      },
      {
        Sid       = "LogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:${local.partition}:s3:::%BUCKET%/AWSLogs/*"
        Condition = local.acl_condition
      },
    ]
    cloudfront_access = [
      {
        Sid       = "LogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = "arn:${local.partition}:s3:::%BUCKET%"
        Condition = local.org_condition
      },
      {
        Sid       = "LogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:${local.partition}:s3:::%BUCKET%/*"
        Condition = local.acl_condition
      },
    ]
    alb_access = [
      {
        Sid       = "AlbLogDelivery"
        Effect    = "Allow"
        Principal = jsondecode(length(var.alb_log_delivery_principal_arns) > 0 ? jsonencode({ AWS = var.alb_log_delivery_principal_arns }) : jsonencode({ Service = "logdelivery.elasticloadbalancing.amazonaws.com" }))
        Action    = "s3:PutObject"
        Resource  = "arn:${local.partition}:s3:::%BUCKET%/AWSLogs/*"
      },
    ]
    state_access = [
      {
        Sid       = "S3ServerAccessLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:${local.partition}:s3:::%BUCKET%/*"
        Condition = local.org_condition
      },
    ]
  }

  deny_insecure_transport = {
    Sid       = "DenyInsecureTransport"
    Effect    = "Deny"
    Principal = "*"
    Action    = "s3:*"
    Resource  = ["arn:${local.partition}:s3:::%BUCKET%", "arn:${local.partition}:s3:::%BUCKET%/*"]
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }

  # The policy is rendered once per bucket: %BUCKET% is replaced with the bucket name.
  bucket_policies = {
    for t, b in local.buckets : t => replace(
      jsonencode({
        Version   = "2012-10-17"
        Statement = concat(local.allow_statements[t], [local.deny_insecure_transport])
      }),
      "%BUCKET%", b.name
    )
  }
}

# ------------------------------------------------------------------------------
# KMS key for the logs
# ------------------------------------------------------------------------------
resource "aws_kms_key" "logs" {
  description             = "Encrypts the central log archive"
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
        # CloudTrail encrypts each log file with a data key. The context pins the key to trails of the management account.
        Sid       = "AllowCloudTrailToEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
          StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:${local.partition}:cloudtrail:*:${var.management_account_id}:trail/*" }
        }
      },
      {
        Sid       = "AllowLogDeliveryServicesToEncrypt"
        Effect    = "Allow"
        Principal = { Service = ["config.amazonaws.com", "delivery.logs.amazonaws.com"] }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
        Condition = local.org_condition
      },
    ]
  })

  tags = local.tags
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name_prefix}-log-archive"
  target_key_id = aws_kms_key.logs.key_id
}

# ------------------------------------------------------------------------------
# One Object Lock bucket per log type
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  # A log bucket that logs to itself is circular, and access to these buckets is recorded by the org trail
  # (S3 data events, PLAN 4.2). Replication would copy audit evidence out of the archive account, and event
  # notifications have no consumer here.
  #checkov:skip=CKV_AWS_18: "Server access logging on a log bucket is circular; the org trail records S3 data events for these buckets (PLAN 4.2)"
  #checkov:skip=CKV_AWS_144: "Cross-region replication is an optional resilience feature planned with PLAN 7.x; Object Lock already protects the logs"
  #checkov:skip=CKV2_AWS_62: "No event consumer exists for log objects"
  #checkov:skip=CKV_AWS_145: "ALB access logs and S3 server access logs cannot be delivered to an SSE-KMS bucket, so those two use SSE-S3; every other log type uses the KMS key"
  for_each = local.buckets

  bucket              = each.value.name
  object_lock_enabled = true
  force_destroy       = false

  tags = merge(local.tags, { Name = each.value.name, LogType = each.key, DataClassification = "confidential" })
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Two resources instead of one conditional: the algorithm is a literal in each, so it is checkable
# (Checkov cannot evaluate a conditional algorithm) and readable.
resource "aws_s3_bucket_server_side_encryption_configuration" "kms" {
  for_each = { for t, b in local.buckets : t => b if b.kms }

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse_s3" {
  for_each = { for t, b in local.buckets : t => b if !b.kms }

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = each.value.retention
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    id     = "archive-then-expire"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = each.value.retention > var.glacier_transition_days ? [1] : []
      content {
        days          = var.glacier_transition_days
        storage_class = "GLACIER"
      }
    }

    expiration {
      days = each.value.retention + var.expire_after_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = each.value.retention + var.expire_after_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_policy" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id
  policy = local.bucket_policies[each.key]

  depends_on = [aws_s3_bucket_public_access_block.this]
}
