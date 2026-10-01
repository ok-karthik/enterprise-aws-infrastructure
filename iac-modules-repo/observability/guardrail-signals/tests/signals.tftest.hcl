# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

variables {
  log_group_name = "/aws/cloudtrail/org"
}

run "one_filter_and_alarm_per_signal" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.this) == 6 && length(aws_cloudwatch_metric_alarm.this) == 6
    error_message = "Six signals: CloudTrail, Config, GuardDuty, Security Hub, root and break-glass."
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.this : a.threshold == 1 && a.treat_missing_data == "notBreaching" && a.statistic == "Sum"])
    error_message = "Every alarm fires on the first event and stays quiet when there is no data."
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.this) == 0
    error_message = "No dashboard unless create_dashboard is true."
  }
}

run "alarms_notify_the_topic" {
  command = plan

  variables {
    alarm_topic_arn = "arn:aws:sns:eu-central-1:111122223333:security-alerts"
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.this : contains(a.alarm_actions, "arn:aws:sns:eu-central-1:111122223333:security-alerts")])
    error_message = "Each alarm must notify the topic."
  }
}

run "dashboard_only_account_creates_no_alarms" {
  command = plan

  variables {
    create_alarms      = false
    log_group_name     = ""
    create_dashboard   = true
    metrics_account_id = "954171757349"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 0 && length(aws_cloudwatch_dashboard.this) == 1
    error_message = "The observability account only gets the dashboard."
  }

  assert {
    condition     = strcontains(aws_cloudwatch_dashboard.this[0].dashboard_body, "954171757349")
    error_message = "The dashboard must read the metrics from the source account."
  }
}

run "log_group_required_for_alarms" {
  command = plan

  variables {
    log_group_name = ""
  }

  expect_failures = [var.log_group_name]
}

run "bad_account_id_is_rejected" {
  command = plan

  variables {
    create_dashboard   = true
    metrics_account_id = "1234"
  }

  expect_failures = [var.metrics_account_id]
}
