# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

variables {
  account_name        = "workloads-dev"
  monthly_limit       = 50
  notification_emails = ["me+alerts@mydomain.test"]
}

run "budget_alerts_at_50_80_100_actual_and_100_forecast" {
  command = plan

  assert {
    condition     = aws_budgets_budget.monthly.limit_amount == "50" && aws_budgets_budget.monthly.limit_unit == "USD" && aws_budgets_budget.monthly.time_unit == "MONTHLY"
    error_message = "A monthly budget with the limit from the registry."
  }

  assert {
    condition     = toset([for n in aws_budgets_budget.monthly.notification : "${n.notification_type}-${n.threshold}"]) == toset(["ACTUAL-50", "ACTUAL-80", "ACTUAL-100", "FORECASTED-100"])
    error_message = "Alerts at 50/80/100 % of actual and 100 % of forecast."
  }

  assert {
    condition     = alltrue([for n in aws_budgets_budget.monthly.notification : n.subscriber_email_addresses == toset(["me+alerts@mydomain.test"])])
    error_message = "Every alert goes to the notification emails."
  }
}

run "anomaly_detection_is_on" {
  command = plan

  assert {
    condition     = aws_ce_anomaly_monitor.services.monitor_dimension == "SERVICE" && aws_ce_anomaly_subscription.daily.frequency == "DAILY"
    error_message = "A per-service anomaly monitor with a daily email report."
  }
}

run "placeholder_email_is_rejected" {
  command = plan

  variables {
    notification_emails = ["aws+management@example.com"]
  }

  expect_failures = [var.notification_emails]
}

run "no_email_is_rejected" {
  command = plan

  variables {
    notification_emails = []
  }

  expect_failures = [var.notification_emails]
}

run "zero_budget_is_rejected" {
  command = plan

  variables {
    monthly_limit = 0
  }

  expect_failures = [var.monthly_limit]
}
