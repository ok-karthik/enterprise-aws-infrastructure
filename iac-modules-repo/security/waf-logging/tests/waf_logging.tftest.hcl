# Tests for security/waf-logging (PLAN 6.2)

# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

run "defaults" {
  command = plan

  variables {
    log_archive_bucket_arn  = "arn:aws:s3:::aws-waf-logs-platform-222222222222-eu-central-1"
    log_archive_kms_key_arn = "arn:aws:kms:eu-central-1:222222222222:key/test-key-id"
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.waf_logs.name == "aws-waf-logs-platform"
    error_message = "Firehose stream name should start with aws-waf-logs- and use the default prefix."
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.waf_logs.destination == "extended_s3"
    error_message = "Firehose destination should be extended_s3."
  }
}

run "custom_prefix" {
  command = plan

  variables {
    name_prefix             = "myorg"
    log_archive_bucket_arn  = "arn:aws:s3:::aws-waf-logs-myorg-222222222222-eu-central-1"
    log_archive_kms_key_arn = "arn:aws:kms:eu-central-1:222222222222:key/test-key-id"
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.waf_logs.name == "aws-waf-logs-myorg"
    error_message = "Firehose stream name should use the custom prefix."
  }
}

run "bad_prefix" {
  command = plan

  variables {
    name_prefix             = "X"
    log_archive_bucket_arn  = "arn:aws:s3:::test"
    log_archive_kms_key_arn = "arn:aws:kms:eu-central-1:222222222222:key/test"
  }

  expect_failures = [var.name_prefix]
}

run "bad_buffering" {
  command = plan

  variables {
    buffering_interval      = 10
    log_archive_bucket_arn  = "arn:aws:s3:::test"
    log_archive_kms_key_arn = "arn:aws:kms:eu-central-1:222222222222:key/test"
  }

  expect_failures = [var.buffering_interval]
}
