# Central alerting (PLAN 4.5): one EventBridge rule per alert type, an encrypted SNS topic, email
# subscriptions. Which rules are created depends on where this is applied (var.enable_*):
#   - security-tooling: GuardDuty and Security Hub findings, which land there because it is the delegated
#     administrator for both services (PLAN 4.4).
#   - management: root sign-in / root API calls and Organizations policy changes, both of which only happen
#     in the management account (root credentials in member accounts are removed, PLAN 3.5; Organizations is
#     only managed centrally).
# BreakGlassAdmin sign-in is already alerted per account by security/break-glass-alerts; this module does not
# duplicate it. CloudTrail management events must be on for EventBridge to see the CloudTrail-derived rules
# (root sign-in, policy changes) — they are, by default.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  topic_name = "${var.name_prefix}-alerts"

  tags = merge({ Service = "security-alerts", ManagedBy = "Terragrunt-Wrapper" }, var.tags)

  # One object with every possible rule (never a conditional expression building it, so there is no ternary
  # type to unify: each key's value is free to have its own shape), filtered down to the enabled ones below.
  all_rules = {
    guardduty_finding = {
      description = "GuardDuty finding with severity >= ${var.guardduty_minimum_severity}"
      pattern = {
        source        = ["aws.guardduty"]
        "detail-type" = ["GuardDuty Finding"]
        detail = {
          severity = [{ numeric = [">=", var.guardduty_minimum_severity] }]
        }
      }
      input_paths = {
        severity = "$.detail.severity"
        type     = "$.detail.type"
        account  = "$.detail.accountId"
        title    = "$.detail.title"
      }
      input_template = "\"GuardDuty finding (severity <severity>) in account <account>: <type> - <title>\""
    }
    securityhub_finding = {
      description = "Security Hub finding imported with severity in ${jsonencode(var.securityhub_severity_labels)}"
      pattern = {
        source        = ["aws.securityhub"]
        "detail-type" = ["Security Hub Findings - Imported"]
        detail = {
          findings = {
            Severity = { Label = var.securityhub_severity_labels }
          }
        }
      }
      # EventBridge event patterns can filter on an array of findings, but the input transformer can only read
      # one path per key: this surfaces the first finding in the event. A batch of several findings still
      # raises one alert (with the first finding's detail), it does not lose the event.
      input_paths = {
        severity = "$.detail.findings[0].Severity.Label"
        title    = "$.detail.findings[0].Title"
        account  = "$.detail.findings[0].AwsAccountId"
      }
      input_template = "\"Security Hub finding (<severity>) in account <account>: <title>\""
    }
    root_console_sign_in = {
      description = "Root user signed in to the console"
      pattern = {
        "detail-type" = ["AWS Console Sign In via CloudTrail"]
        detail        = { userIdentity = { type = ["Root"] } }
      }
      input_paths = {
        account = "$.account"
        who     = "$.detail.userIdentity.arn"
        ip      = "$.detail.sourceIPAddress"
        time    = "$.time"
      }
      input_template = "\"ROOT SIGN-IN (console) in account <account> by <who> from <ip> at <time>. If nobody expected this, treat it as an incident (docs/BREAK_GLASS.md).\""
    }
    root_api_call = {
      description = "An API call was made directly as the root user (not through a role, not an AWS service)"
      pattern = {
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          userIdentity = {
            type      = ["Root"]
            invokedBy = [{ exists = false }]
          }
        }
      }
      input_paths = {
        account = "$.account"
        event   = "$.detail.eventName"
        ip      = "$.detail.sourceIPAddress"
        time    = "$.time"
      }
      input_template = "\"ROOT API CALL <event> in account <account> from <ip> at <time>. If nobody expected this, treat it as an incident (docs/BREAK_GLASS.md).\""
    }
    scp_change = {
      description = "An Organizations policy (SCP, RCP, tag, backup, declarative) was created, changed, deleted, attached, detached, or a policy type was enabled/disabled"
      pattern = {
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["organizations.amazonaws.com"]
          eventName = [
            "CreatePolicy", "UpdatePolicy", "DeletePolicy",
            "AttachPolicy", "DetachPolicy",
            "EnablePolicyType", "DisablePolicyType",
          ]
        }
      }
      input_paths = {
        who   = "$.detail.userIdentity.arn"
        event = "$.detail.eventName"
        time  = "$.time"
      }
      input_template = "\"ORGANIZATION POLICY CHANGE <event> by <who> at <time>. Review it against an approved change.\""
    }
  }

  rule_enabled = {
    guardduty_finding    = var.enable_guardduty_findings
    securityhub_finding  = var.enable_securityhub_findings
    root_console_sign_in = var.enable_root_sign_in
    root_api_call        = var.enable_root_sign_in
    scp_change           = var.enable_scp_changes
  }

  rules = { for name, rule in local.all_rules : name => rule if local.rule_enabled[name] }

  rule_arns = [for name, _ in local.rules : "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/${var.name_prefix}-${replace(name, "_", "-")}"]
}

# ------------------------------------------------------------------------------
# Encrypted topic (the org's encryption rule requires a KMS key on every SNS topic)
# ------------------------------------------------------------------------------
resource "aws_kms_key" "alerts" {
  description             = "Encrypts the ${var.name_prefix} topic"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIamPolicies"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowEventBridgeToPublishEncrypted"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = { ArnEquals = { "aws:SourceArn" = local.rule_arns } }
      },
    ]
  })

  tags = local.tags
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${local.topic_name}"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "alerts" {
  name              = local.topic_name
  display_name      = "Security alerts"
  kms_master_key_id = aws_kms_key.alerts.arn

  tags = local.tags
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAlertRulesToPublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
      Condition = { ArnEquals = { "aws:SourceArn" = local.rule_arns } }
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notification_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ------------------------------------------------------------------------------
# Rules and targets
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name          = "${var.name_prefix}-${replace(each.key, "_", "-")}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.pattern)

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "sns" {
  for_each = local.rules

  rule = aws_cloudwatch_event_rule.this[each.key].name
  arn  = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths    = each.value.input_paths
    input_template = each.value.input_template
  }
}
