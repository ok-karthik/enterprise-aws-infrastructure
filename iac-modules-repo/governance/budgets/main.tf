# Budgets from day one: a monthly cost budget per account with alerts at 50 / 80 / 100 % of the actual
# spend and at 100 % of the forecast, plus a Cost Anomaly Detection monitor per account. Applied in every
# account; in the management account the budget covers the whole organization.

locals {
  # 50 / 80 / 100 % actual, 100 % forecast: an early nudge, a warning, the limit reached, and "you will
  # reach it before the month ends".
  notifications = [
    { threshold = 50, type = "ACTUAL" },
    { threshold = 80, type = "ACTUAL" },
    { threshold = 100, type = "ACTUAL" },
    { threshold = 100, type = "FORECASTED" },
  ]

  tags = merge(
    {
      Service   = "governance-budgets"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.account_name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_limit)
  limit_unit   = var.currency
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = local.notifications

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = var.notification_emails
      subscriber_sns_topic_arns  = var.notification_sns_topic_arns
    }
  }

  tags = local.tags
}

# Cost Anomaly Detection: one monitor across the account's services, reported daily by email.
resource "aws_ce_anomaly_monitor" "services" {
  name              = "${var.account_name}-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = local.tags
}

resource "aws_ce_anomaly_subscription" "daily" {
  name             = "${var.account_name}-anomalies"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]

  dynamic "subscriber" {
    for_each = toset(var.notification_emails)

    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold)]
    }
  }

  tags = local.tags
}
