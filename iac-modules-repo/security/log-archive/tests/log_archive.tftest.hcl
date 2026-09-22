# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
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
      arn    = "arn:aws:kms:eu-central-1:222233334444:key/11111111-2222-3333-4444-555555555555"
      key_id = "11111111-2222-3333-4444-555555555555"
    }
  }
}

variables {
  organization_id       = "o-abcde12345"
  management_account_id = "111122223333"
}

run "one_bucket_per_log_type_with_contract_names" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket.this) == 7
    error_message = "Every log type gets a bucket."
  }

  assert {
    condition     = output.bucket_names["cloudtrail"] == "platform-cloudtrail-222233334444-eu-central-1"
    error_message = "The CloudTrail bucket name is a contract with the org-cloudtrail leaf: <prefix>-cloudtrail-<account id>-<region>."
  }

  assert {
    condition     = startswith(output.bucket_names["waf"], "aws-waf-logs-")
    error_message = "WAF log buckets must start with aws-waf-logs-."
  }
}

run "object_lock_is_compliance_with_400_days_for_cloudtrail" {
  command = plan

  assert {
    condition     = alltrue([for k, c in aws_s3_bucket_object_lock_configuration.this : one(c.rule).default_retention[0].mode == "COMPLIANCE"])
    error_message = "Object Lock must be in COMPLIANCE mode."
  }

  assert {
    condition     = one(aws_s3_bucket_object_lock_configuration.this["cloudtrail"].rule).default_retention[0].days == 400 && one(aws_s3_bucket_object_lock_configuration.this["config"].rule).default_retention[0].days == 400
    error_message = "CloudTrail and Config default to 400 days."
  }

  assert {
    condition     = one(aws_s3_bucket_object_lock_configuration.this["waf"].rule).default_retention[0].days == 90
    error_message = "Other log types default to 90 days."
  }

  assert {
    condition     = alltrue([for k, b in aws_s3_bucket.this : b.object_lock_enabled])
    error_message = "Every bucket must be created with Object Lock enabled."
  }
}

run "retention_is_a_variable" {
  command = plan

  variables {
    retention_days = { cloudtrail = 730 }
  }

  assert {
    condition     = one(aws_s3_bucket_object_lock_configuration.this["cloudtrail"].rule).default_retention[0].days == 730
    error_message = "retention_days must override the default."
  }
}

run "lifecycle_archives_long_retention_and_expires_after_it" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this["cloudtrail"].rule).transition).storage_class == "GLACIER"
    error_message = "CloudTrail (400 days) moves to Glacier."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this["cloudtrail"].rule).expiration[0].days == 430
    error_message = "Expiry is retention + 30 days, never before the lock ends."
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this["waf"].rule).transition) == 0
    error_message = "A 90-day log is not moved to Glacier (its minimum storage duration would exceed the retention)."
  }
}

run "buckets_are_encrypted_public_access_is_blocked_and_tls_is_required" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.kms["cloudtrail"].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "CloudTrail logs use the KMS key."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.sse_s3["alb_access"].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" && one(aws_s3_bucket_server_side_encryption_configuration.sse_s3["state_access"].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "ALB and S3 server access logs only support SSE-S3."
  }

  assert {
    condition     = alltrue([for k, p in aws_s3_bucket_public_access_block.this : p.block_public_acls && p.block_public_policy && p.ignore_public_acls && p.restrict_public_buckets])
    error_message = "All four public access blocks must be on."
  }

  assert {
    condition     = alltrue([for k, p in aws_s3_bucket_policy.this : anytrue([for s in jsondecode(p.policy).Statement : s.Sid == "DenyInsecureTransport" && s.Effect == "Deny"])])
    error_message = "Every bucket policy must deny non-TLS requests."
  }
}

run "policies_only_admit_the_organization_and_its_trail" {
  command = plan

  assert {
    condition     = alltrue([for s in jsondecode(aws_s3_bucket_policy.this["cloudtrail"].policy).Statement : s.Effect == "Deny" || s.Condition.StringEquals["aws:SourceArn"] == "arn:aws:cloudtrail:eu-central-1:111122223333:trail/platform-org-trail"])
    error_message = "The CloudTrail bucket only accepts the organization trail of the management account."
  }

  assert {
    condition     = alltrue([for t in ["config", "vpc_flow_logs", "waf", "cloudfront_access", "state_access"] : alltrue([for s in jsondecode(aws_s3_bucket_policy.this[t].policy).Statement : s.Effect == "Deny" || s.Condition.StringEquals["aws:SourceOrgID"] == "o-abcde12345"])])
    error_message = "Service deliveries must be limited with aws:SourceOrgID."
  }

  assert {
    condition     = strcontains(aws_s3_bucket_policy.this["cloudtrail"].policy, "AWSLogs/o-abcde12345/*") && strcontains(aws_s3_bucket_policy.this["cloudtrail"].policy, "AWSLogs/111122223333/*")
    error_message = "The organization trail writes under AWSLogs/<org id>/ and AWSLogs/<management account id>/."
  }
}

run "alb_uses_the_service_principal_when_no_account_is_given" {
  command = plan

  variables {
    alb_log_delivery_principal_arns = []
  }

  assert {
    condition     = strcontains(aws_s3_bucket_policy.this["alb_access"].policy, "logdelivery.elasticloadbalancing.amazonaws.com")
    error_message = "An empty principal list falls back to the ELB log delivery service principal."
  }
}

run "placeholder_organization_id_is_rejected" {
  command = plan

  variables {
    organization_id = "o-0000000000"
  }

  expect_failures = [var.organization_id]
}

run "placeholder_management_account_is_rejected" {
  command = plan

  variables {
    management_account_id = "000000000001"
  }

  expect_failures = [var.management_account_id]
}

run "unknown_log_type_is_rejected" {
  command = plan

  variables {
    enabled_log_types = ["cloudtrail", "vpc"]
  }

  expect_failures = [var.enabled_log_types]
}
