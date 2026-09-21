# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
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
      arn    = "arn:aws:kms:eu-central-1:111122223333:key/11111111-2222-3333-4444-555555555555"
      key_id = "11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:eu-central-1:111122223333:break-glass-alerts"
    }
  }
}

variables {
  notification_emails = ["me+breakglass@mydomain.test"]
}

run "member_account_watches_saml_and_console_sign_in" {
  command = plan

  assert {
    condition     = toset(keys(aws_cloudwatch_event_rule.this)) == toset(["saml_assume_role", "console_login"])
    error_message = "A member account has the STS and console rules, and no portal rule."
  }

  assert {
    condition     = strcontains(aws_cloudwatch_event_rule.this["saml_assume_role"].event_pattern, "AssumeRoleWithSAML") && strcontains(aws_cloudwatch_event_rule.this["saml_assume_role"].event_pattern, "*AWSReservedSSO_BreakGlassAdmin_*")
    error_message = "The STS rule must match AssumeRoleWithSAML of the BreakGlassAdmin role."
  }

  assert {
    condition     = strcontains(aws_cloudwatch_event_rule.this["console_login"].event_pattern, "AWS Console Sign In via CloudTrail") && strcontains(aws_cloudwatch_event_rule.this["console_login"].event_pattern, "*AWSReservedSSO_BreakGlassAdmin_*")
    error_message = "The console rule must match a console sign-in as the BreakGlassAdmin role."
  }
}

run "management_account_also_watches_the_sso_portal" {
  command = plan

  variables {
    enable_sso_portal_rule = true
  }

  assert {
    condition     = contains(keys(aws_cloudwatch_event_rule.this), "sso_portal") && strcontains(aws_cloudwatch_event_rule.this["sso_portal"].event_pattern, "GetRoleCredentials") && strcontains(aws_cloudwatch_event_rule.this["sso_portal"].event_pattern, "Federate")
    error_message = "The portal rule shows CLI sign-ins and is logged in the management account."
  }
}

run "another_permission_set_name_is_followed" {
  command = plan

  variables {
    permission_set_name = "PlatformEngineerJit"
  }

  assert {
    condition     = strcontains(aws_cloudwatch_event_rule.this["saml_assume_role"].event_pattern, "*AWSReservedSSO_PlatformEngineerJit_*")
    error_message = "The rules follow the configured permission set."
  }
}

# apply (against the mock provider) because the policy embeds the topic ARN, known only after apply
run "topic_is_encrypted_and_only_the_rules_can_publish" {
  command = apply

  assert {
    condition     = aws_kms_key.alerts.enable_key_rotation && aws_sns_topic.alerts.kms_master_key_id != ""
    error_message = "The topic must be encrypted with a rotating CMK."
  }

  assert {
    condition     = strcontains(aws_sns_topic_policy.alerts.policy, "events.amazonaws.com") && strcontains(aws_sns_topic_policy.alerts.policy, "arn:aws:events:eu-central-1:111122223333:rule/break-glass-saml-assume-role") && strcontains(aws_sns_topic_policy.alerts.policy, "aws:SourceArn")
    error_message = "Only the break-glass rules of this account may publish to the topic."
  }

  assert {
    condition     = strcontains(aws_kms_key.alerts.policy, "AllowEventBridgeToPublishEncrypted") && strcontains(aws_kms_key.alerts.policy, "aws:SourceArn")
    error_message = "EventBridge must be allowed to encrypt for the topic, and only for these rules."
  }
}

run "every_email_is_subscribed" {
  command = plan

  variables {
    notification_emails = ["me+a@mydomain.test", "me+b@mydomain.test"]
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 2 && alltrue([for _, s in aws_sns_topic_subscription.email : s.protocol == "email"])
    error_message = "One email subscription per address."
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
