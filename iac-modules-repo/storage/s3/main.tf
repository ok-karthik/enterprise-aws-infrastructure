terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

# S3 bucket names live in one global namespace; random suffix prevents collision.
resource "random_string" "bucket_suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  raw_prefix  = lower("${var.team_name}-${var.app_name}-${var.env}")
  bucket_name = "${substr(local.raw_prefix, 0, 56)}-${random_string.bucket_suffix.result}"
}

resource "aws_s3_bucket" "this" {
  # Optional features that need infrastructure this module does not own or that cost money. Each is a decision for
  # the tenant or for a later phase, not a baseline guardrail (the guardrails are the resources below).
  #checkov:skip=CKV_AWS_145: "SSE-S3 (AES256) is the contract of this capability (see the README) and is cheaper than a KMS key per bucket; a customer-managed key is an opt-in for confidential data"
  #checkov:skip=CKV_AWS_18: "Server access logging needs a log-archive bucket, which comes with PLAN 4.1; CloudTrail data events cover confidential buckets (PLAN 4.2)"
  #checkov:skip=CKV_AWS_144: "Cross-region replication doubles storage cost and needs a second region; it is an optional flag planned in PLAN 7.3"
  #checkov:skip=CKV2_AWS_62: "Event notifications are an integration a tenant adds when it has a consumer; there is none by default"
  bucket = local.bucket_name

  tags = merge(
    {
      Name      = local.bucket_name
      Owner     = var.team_name
      ManagedBy = "Terragrunt-Wrapper"
      Service   = "storage-s3"
    },
    var.tags
  )
}

# Guardrails enforced for all tenants
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle: abort multipart uploads that were never completed (they are invisible in the bucket and billed).
# Nothing else expires: retention of the tenant's data and of old object versions is the tenant's decision.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Versioning must exist before the lifecycle configuration is applied.
  depends_on = [aws_s3_bucket_versioning.this]
}
