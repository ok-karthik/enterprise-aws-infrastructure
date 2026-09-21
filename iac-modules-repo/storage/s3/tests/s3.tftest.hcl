# Offline unit tests (no AWS credentials): `terraform test` from this module directory.
# They pin the guardrails and the lifecycle rule added for the Checkov backlog (PLAN 8.9).

mock_provider "aws" {}
mock_provider "random" {}

variables {
  team_name = "payments"
  app_name  = "ledger"
}

run "incomplete_multipart_uploads_are_aborted" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).id == "abort-incomplete-multipart-uploads"
    error_message = "The lifecycle rule for incomplete multipart uploads is missing."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).status == "Enabled"
    error_message = "The lifecycle rule must be enabled."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).abort_incomplete_multipart_upload).days_after_initiation == 7
    error_message = "Incomplete multipart uploads must be aborted after 7 days."
  }
}

run "guardrails_stay_on" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.ignore_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "All four public access blocks must be on."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.this.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled."
  }
}
