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
