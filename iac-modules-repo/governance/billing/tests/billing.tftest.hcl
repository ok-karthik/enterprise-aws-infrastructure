# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "954171757349"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

variables {
  anomaly_alert_emails = ["finops@corp.test"]
}

run "export_is_daily_parquet_and_the_bucket_is_locked_down" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  assert {
    condition     = one(aws_bcmdataexports_export.cur.export).name == "platform-billing-cur2" && one(one(one(one(aws_bcmdataexports_export.cur.export).destination_configurations).s3_destination).s3_output_configurations).format == "PARQUET"
    error_message = "The export is a CUR 2.0 export in Parquet."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.cur.block_public_acls && aws_s3_bucket_public_access_block.cur.block_public_policy && aws_s3_bucket_public_access_block.cur.ignore_public_acls && aws_s3_bucket_public_access_block.cur.restrict_public_buckets
    error_message = "The export bucket must block all public access."
  }
}

run "one_monitor_per_ou_plus_the_service_monitor" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    anomaly_ou_accounts = {
      Prod    = ["111122223333"]
      NonProd = ["444455556666", "777788889999"]
      Empty   = []
    }
  }

  assert {
    condition     = length(aws_ce_anomaly_monitor.ou) == 2 && contains(keys(aws_ce_anomaly_monitor.ou), "Prod") && contains(keys(aws_ce_anomaly_monitor.ou), "NonProd")
    error_message = "One custom monitor per OU that has accounts; an empty OU gets none."
  }

  assert {
    condition     = length(aws_ce_anomaly_subscription.daily.monitor_arn_list) == 3
    error_message = "The subscription covers the service monitor and both OU monitors."
  }
}

run "no_cost_allocation_tags_by_default" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  assert {
    condition     = length(aws_ce_cost_allocation_tag.this) == 0
    error_message = "Tags are activated only when listed."
  }
}

run "cost_allocation_tag_is_activated_when_listed" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    cost_allocation_tags = ["CostCenter"]
  }

  assert {
    condition     = aws_ce_cost_allocation_tag.this["CostCenter"].status == "Active"
    error_message = "CostCenter must be activated."
  }
}

run "example_email_is_rejected" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    anomaly_alert_emails = ["aws+finops@example.com"]
  }

  expect_failures = [var.anomaly_alert_emails]
}

run "bad_account_id_is_rejected" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    anomaly_ou_accounts = { Prod = ["12345"] }
  }

  expect_failures = [var.anomaly_ou_accounts]
}
