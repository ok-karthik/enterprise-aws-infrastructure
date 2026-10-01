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

run "replication_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_replication_configuration.this) == 0 && length(aws_iam_role.replication) == 0
    error_message = "No replication resources unless replication_destination_bucket_arn is set."
  }
}

run "replication_when_a_destination_is_given" {
  command = plan

  variables {
    replication_destination_bucket_arn = "arn:aws:s3:::payments-ledger-dr-abc123"
  }

  assert {
    condition     = one(aws_s3_bucket_replication_configuration.this[0].rule).status == "Enabled" && one(one(aws_s3_bucket_replication_configuration.this[0].rule).delete_marker_replication).status == "Disabled"
    error_message = "Replication must be enabled and must not copy deletes."
  }
}

run "bad_destination_arn_is_rejected" {
  command = plan

  variables {
    replication_destination_bucket_arn = "not-an-arn"
  }

  expect_failures = [var.replication_destination_bucket_arn]
}
