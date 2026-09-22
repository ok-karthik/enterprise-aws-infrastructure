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

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:eu-central-1:222233334444:security-alerts-alerts"
    }
  }
}

variables {
  notification_emails = ["secops@example.org"]
}

run "no_rules_enabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_rule.this) == 0
    error_message = "Every enable_* flag defaults to false: nothing is created until a call opts in."
  }

  assert {
    condition     = length(output.enabled_rules) == 0
    error_message = "The output must be empty with nothing enabled."
  }
}

run "security_tooling_profile_enables_guardduty_and_securityhub" {
  command = plan

  variables {
    enable_guardduty_findings   = true
    enable_securityhub_findings = true
  }

  assert {
    condition     = output.enabled_rules == tolist(["guardduty_finding", "securityhub_finding"])
    error_message = "Only the GuardDuty and Security Hub rules must be created."
  }

  assert {
    condition = one([for r in aws_cloudwatch_event_rule.this : r if r.name == "security-alerts-guardduty-finding"]).event_pattern == jsonencode({
      source        = ["aws.guardduty"]
      "detail-type" = ["GuardDuty Finding"]
      detail = {
        severity = [{ numeric = [">=", 7.0] }]
      }
    })
    error_message = "The GuardDuty rule must filter on severity >= guardduty_minimum_severity."
  }

  assert {
    condition     = strcontains(one([for r in aws_cloudwatch_event_rule.this : r if r.name == "security-alerts-securityhub-finding"]).event_pattern, "\"Label\":[\"HIGH\",\"CRITICAL\"]")
    error_message = "The Security Hub rule must filter on the default severity labels."
  }
}

run "management_profile_enables_root_sign_in_and_scp_changes" {
  command = plan

  variables {
    enable_root_sign_in = true
    enable_scp_changes  = true
  }

  assert {
    condition     = output.enabled_rules == tolist(["root_api_call", "root_console_sign_in", "scp_change"])
    error_message = "Root sign-in must create BOTH the console and the API-call rule, plus the SCP-change rule."
  }

  assert {
    condition     = strcontains(one([for r in aws_cloudwatch_event_rule.this : r if r.name == "security-alerts-root-api-call"]).event_pattern, "\"exists\":false")
    error_message = "The root API-call rule must exclude AWS-service-invoked calls (invokedBy exists:false)."
  }

  assert {
    condition     = strcontains(one([for r in aws_cloudwatch_event_rule.this : r if r.name == "security-alerts-scp-change"]).event_pattern, "organizations.amazonaws.com")
    error_message = "The SCP-change rule must scope to organizations.amazonaws.com."
  }
}

run "every_rule_can_be_enabled_together" {
  command = plan

  variables {
    enable_guardduty_findings   = true
    enable_securityhub_findings = true
    enable_root_sign_in         = true
    enable_scp_changes          = true
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.this) == 5
    error_message = "All five rules must be creatable together (nothing here is mutually exclusive)."
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.sns) == 5
    error_message = "Every rule must have exactly one target: the alert topic."
  }
}

run "topic_only_accepts_publishes_from_this_call_s_own_rules" {
  # apply, not plan: aws_sns_topic_policy.policy is Optional+Computed, so the mock provider leaves it
  # unknown at plan time even though the config sets it explicitly.
  command = apply

  variables {
    enable_guardduty_findings = true
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.alerts.policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == ["arn:aws:events:eu-central-1:222233334444:rule/security-alerts-guardduty-finding"]
    error_message = "The topic policy must scope to the rule ARNs this call actually creates."
  }
}

run "placeholder_email_is_rejected" {
  command = plan

  variables {
    notification_emails = ["secops@example.com"]
  }

  expect_failures = [var.notification_emails]
}

run "unknown_severity_label_is_rejected" {
  command = plan

  variables {
    securityhub_severity_labels = ["EXTREME"]
  }

  expect_failures = [var.securityhub_severity_labels]
}
