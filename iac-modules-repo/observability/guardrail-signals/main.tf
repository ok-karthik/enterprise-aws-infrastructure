# "Are the guardrails still on?" signals (PLAN 9.3). Each signal is a CloudTrail event that means someone weakened a
# control, counted by a log metric filter and alarmed on the first occurrence. The organization trail records every
# member account, so one application in the management account covers the whole organization.

data "aws_region" "current" {}

locals {
  namespace = "Platform/Guardrails"

  # name => {description, pattern}. Patterns are CloudWatch Logs JSON filter patterns over CloudTrail records.
  signals = {
    CloudTrailTampering = {
      description = "CloudTrail logging was stopped, deleted or reconfigured"
      pattern     = "{ ($.eventSource = \"cloudtrail.amazonaws.com\") && (($.eventName = \"StopLogging\") || ($.eventName = \"DeleteTrail\") || ($.eventName = \"UpdateTrail\") || ($.eventName = \"PutEventSelectors\")) }"
    }
    ConfigRecorderStopped = {
      description = "The AWS Config recorder or delivery channel was stopped or deleted"
      pattern     = "{ ($.eventSource = \"config.amazonaws.com\") && (($.eventName = \"StopConfigurationRecorder\") || ($.eventName = \"DeleteConfigurationRecorder\") || ($.eventName = \"DeleteDeliveryChannel\")) }"
    }
    GuardDutyDisabled = {
      description = "GuardDuty was disabled or its detector deleted in some account"
      pattern     = "{ ($.eventSource = \"guardduty.amazonaws.com\") && (($.eventName = \"DeleteDetector\") || ($.eventName = \"DisableOrganizationAdminAccount\") || ($.eventName = \"StopMonitoringMembers\") || ($.eventName = \"DisassociateFromMasterAccount\")) }"
    }
    SecurityHubDisabled = {
      description = "Security Hub or one of its standards was disabled in some account"
      pattern     = "{ ($.eventSource = \"securityhub.amazonaws.com\") && (($.eventName = \"DisableSecurityHub\") || ($.eventName = \"DisableOrganizationAdminAccount\") || ($.eventName = \"BatchDisableStandards\")) }"
    }
    RootUsage = {
      description = "The root user was used (any account)"
      pattern     = "{ ($.userIdentity.type = \"Root\") && ($.userIdentity.invokedBy NOT EXISTS) && ($.eventType != \"AwsServiceEvent\") }"
    }
    BreakGlassUsage = {
      description = "A BreakGlassAdmin session made an API call (any account)"
      pattern     = "{ $.userIdentity.arn = \"*AWSReservedSSO_BreakGlassAdmin_*\" }"
    }
  }

  alarm_signals     = var.create_alarms ? local.signals : {}
  dashboard_account = var.metrics_account_id == "" ? {} : { accountId = var.metrics_account_id }
}

resource "aws_cloudwatch_log_metric_filter" "this" {
  for_each = local.alarm_signals

  name           = "${var.name_prefix}-${each.key}"
  log_group_name = var.log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.key
    namespace     = local.namespace
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarm_signals

  alarm_name          = "${var.name_prefix}-${each.key}"
  alarm_description   = each.value.description
  namespace           = local.namespace
  metric_name         = each.key
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_topic_arn == "" ? [] : [var.alarm_topic_arn]
  tags          = var.tags

  depends_on = [aws_cloudwatch_log_metric_filter.this]
}

resource "aws_cloudwatch_dashboard" "this" {
  count = var.create_dashboard ? 1 : 0

  dashboard_name = "${var.name_prefix}-are-the-guardrails-on"
  dashboard_body = jsonencode({
    widgets = concat(
      [{
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "## Are the guardrails on?\nEach tile counts events in the last 24 hours that weaken a control. **Anything above 0 needs a person to look.** Source: the organization CloudTrail, one alarm per tile."
        }
      }],
      [
        for i, name in sort(keys(local.signals)) : {
          type   = "metric"
          x      = (i % 4) * 6
          y      = 2 + floor(i / 4) * 4
          width  = 6
          height = 4
          properties = {
            title   = name
            view    = "singleValue"
            stat    = "Sum"
            period  = 86400
            region  = data.aws_region.current.region
            metrics = [[local.namespace, name, local.dashboard_account]]
          }
        }
      ]
    )
  })
}
