# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  # Plan-time comparisons need known ARNs/names for the resources that support the trail; the default smart
  # mock leaves computed attributes (and, without these, data source reads too) unknown until apply.
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "222233334444"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:eu-central-1:222233334444:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      key_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::222233334444:role/platform-org-trail-cloudwatch-delivery"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-central-1:222233334444:log-group:/aws/cloudtrail/platform-org-trail"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:eu-central-1:222233334444:platform-org-trail-notifications"
    }
  }
}

variables {
  log_archive_bucket_name = "platform-cloudtrail-222233334444-eu-central-1"
  kms_key_arn             = "arn:aws:kms:eu-central-1:222233334444:key/11111111-2222-3333-4444-555555555555"
}

run "trail_is_organization_wide_multi_region_and_validated" {
  command = plan

  assert {
    condition     = aws_cloudtrail.org.is_organization_trail && aws_cloudtrail.org.is_multi_region_trail && aws_cloudtrail.org.enable_log_file_validation
    error_message = "The trail must be organization-wide, multi-region, and log file validation must be on."
  }

  assert {
    condition     = aws_cloudtrail.org.kms_key_id == var.kms_key_arn
    error_message = "The trail must encrypt with the log-archive KMS key."
  }

  assert {
    condition     = aws_cloudtrail.org.s3_bucket_name == var.log_archive_bucket_name
    error_message = "The trail must deliver to the log-archive bucket."
  }

  assert {
    condition     = length(aws_cloudtrail.org.advanced_event_selector) == 0
    error_message = "With no confidential buckets, no advanced_event_selector is added (the trail logs management events by default)."
  }
}

run "trail_delivers_to_cloudwatch_logs_and_sns" {
  # apply, not plan: several AWS provider attributes here are Optional+Computed, so the mock provider
  # leaves them unknown at plan time even when the config sets them explicitly.
  command = apply

  assert {
    condition     = aws_cloudtrail.org.cloud_watch_logs_group_arn == "${aws_cloudwatch_log_group.org_trail.arn}:*"
    error_message = "The trail must deliver to the CloudWatch Logs group (with the :* suffix CloudTrail requires)."
  }

  assert {
    condition     = aws_cloudtrail.org.cloud_watch_logs_role_arn == aws_iam_role.cloudtrail_to_cloudwatch.arn
    error_message = "The trail must use the CloudWatch delivery role."
  }

  assert {
    condition     = aws_cloudtrail.org.sns_topic_name == aws_sns_topic.trail_notifications.name
    error_message = "The trail must publish log-delivery notifications to the SNS topic."
  }

  assert {
    condition     = anytrue([for s in jsondecode(aws_sns_topic_policy.trail_notifications.policy).Statement : s.Principal.Service == "cloudtrail.amazonaws.com" && can(regex("^arn:aws:cloudtrail:[a-z0-9-]+:[0-9]{12}:trail/${var.trail_name}$", s.Condition.StringEquals["aws:SourceArn"]))])
    error_message = "Only this trail may publish to its notification topic."
  }

  assert {
    condition     = aws_cloudwatch_log_group.org_trail.kms_key_id == aws_kms_key.trail_support.arn
    error_message = "The CloudWatch Logs group must be encrypted with the local KMS key (not the cross-account log-archive key)."
  }
}

run "confidential_buckets_add_data_events_and_keep_management_events" {
  command = plan

  variables {
    confidential_s3_bucket_arns = ["arn:aws:s3:::tenant-payments-ledger-abc123"]
  }

  assert {
    condition     = length(aws_cloudtrail.org.advanced_event_selector) == 2
    error_message = "One selector for management events, one for S3 data events."
  }

  assert {
    condition     = anytrue([for s in aws_cloudtrail.org.advanced_event_selector : s.name == "ManagementEvents"])
    error_message = "Management events must still be logged when data events are added."
  }

  assert {
    condition = anytrue([
      for s in aws_cloudtrail.org.advanced_event_selector : (
        s.name == "S3DataEventsForConfidentialBuckets" ?
        lookup({ for f in s.field_selector : f.field => f.starts_with }, "resources.ARN", null) == tolist(["arn:aws:s3:::tenant-payments-ledger-abc123/"]) :
        false
      )
    ])
    error_message = "The data event selector must scope to the confidential bucket's objects."
  }
}

run "cloudtrail_lake_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudtrail_event_data_store.org) == 0
    error_message = "CloudTrail Lake must be opt-in."
  }

  assert {
    condition     = output.cloudtrail_lake_arn == null
    error_message = "The output must be null when CloudTrail Lake is off."
  }
}

run "cloudtrail_lake_can_be_enabled" {
  command = plan

  variables {
    enable_cloudtrail_lake = true
  }

  assert {
    condition     = one(aws_cloudtrail_event_data_store.org).organization_enabled && one(aws_cloudtrail_event_data_store.org).multi_region_enabled
    error_message = "The event data store must cover the whole organization and every region."
  }

  assert {
    condition     = one(aws_cloudtrail_event_data_store.org).retention_period == 400
    error_message = "Default retention is 400 days."
  }
}

run "bad_kms_key_arn_is_rejected" {
  command = plan

  variables {
    kms_key_arn = "not-an-arn"
  }

  expect_failures = [var.kms_key_arn]
}

run "non_s3_confidential_arn_is_rejected" {
  command = plan

  variables {
    confidential_s3_bucket_arns = ["arn:aws:dynamodb:eu-central-1:222233334444:table/x"]
  }

  expect_failures = [var.confidential_s3_bucket_arns]
}
