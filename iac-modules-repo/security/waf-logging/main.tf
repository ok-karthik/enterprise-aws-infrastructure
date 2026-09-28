# WAF logging (PLAN 6.2): Kinesis Data Firehose delivery stream that ships WAFv2 logs to the log-archive
# S3 bucket, with redaction of sensitive HTTP headers (authorization, cookie by default).
#
# WAFv2 requires the Firehose delivery stream name to start with "aws-waf-logs-". The Firehose role
# gets write access to the log-archive bucket and encrypt/decrypt on its KMS key.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  tags = merge({ Service = "security-waf-logging", ManagedBy = "Terragrunt-Wrapper" }, var.tags)

  firehose_name = "aws-waf-logs-${var.name_prefix}"
}

# ------------------------------------------------------------------------------
# IAM role for Firehose: write to S3 + use the KMS key
# ------------------------------------------------------------------------------
resource "aws_iam_role" "firehose" {
  name = "${var.name_prefix}-waf-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "FirehoseAssumeRole"
        Effect    = "Allow"
        Principal = { Service = "firehose.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = { StringEquals = { "sts:ExternalId" = local.account_id } }
      },
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "firehose_s3" {
  #checkov:skip=CKV_AWS_355: "The S3 and KMS permissions are scoped to the specific log-archive bucket and its KMS key — this is the minimum required for Firehose delivery"
  name = "firehose-s3-delivery"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Write"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject",
        ]
        Resource = [
          var.log_archive_bucket_arn,
          "${var.log_archive_bucket_arn}/*",
        ]
      },
      {
        Sid    = "KmsEncrypt"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt",
          "kms:DescribeKey",
        ]
        Resource = [var.log_archive_kms_key_arn]
      },
    ]
  })
}

# ------------------------------------------------------------------------------
# Firehose delivery stream: WAF logs → S3 (log-archive bucket)
# ------------------------------------------------------------------------------
resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  #checkov:skip=CKV_AWS_240: "Server-side encryption is handled by the destination S3 bucket's KMS key (log-archive), not at the Firehose stream level"
  #checkov:skip=CKV_AWS_241: "Server-side encryption is handled by the destination S3 bucket's KMS key (log-archive), not at the Firehose stream level; double encryption would add cost without security benefit"
  name        = local.firehose_name
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = var.log_archive_bucket_arn

    prefix              = "AWSLogs/${local.account_id}/WAFLogs/${local.region}/"
    error_output_prefix = "AWSLogs/${local.account_id}/WAFLogs/${local.region}/errors/"

    buffering_interval = var.buffering_interval
    buffering_size     = var.buffering_size

    compression_format = "GZIP"

    kms_key_arn = var.log_archive_kms_key_arn
  }

  tags = local.tags
}

# ------------------------------------------------------------------------------
# WAFv2 logging configuration: attaches to each web ACL and redacts sensitive fields
# ------------------------------------------------------------------------------
resource "aws_wafv2_web_acl_logging_configuration" "this" {
  for_each = toset(var.web_acl_arns)

  resource_arn            = each.value
  log_destination_configs = [aws_kinesis_firehose_delivery_stream.waf_logs.arn]

  dynamic "redacted_fields" {
    for_each = var.redacted_fields
    content {
      dynamic "single_header" {
        for_each = redacted_fields.value.single_header != null ? [redacted_fields.value.single_header] : []
        content {
          name = single_header.value.name
        }
      }
      dynamic "method" {
        for_each = redacted_fields.value.method != null ? [1] : []
        content {}
      }
      dynamic "query_string" {
        for_each = redacted_fields.value.query_string != null ? [1] : []
        content {}
      }
      dynamic "uri_path" {
        for_each = redacted_fields.value.uri_path != null ? [1] : []
        content {}
      }
    }
  }
}
