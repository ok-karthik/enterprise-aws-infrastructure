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

  mock_resource "aws_lambda_function" {
    defaults = {
      arn           = "arn:aws:lambda:eu-central-1:222233334444:function:auto-remediate-open-ssh"
      function_name = "auto-remediate-open-ssh"
    }
  }

  mock_resource "aws_cloudwatch_event_bus" {
    defaults = {
      arn  = "arn:aws:events:eu-central-1:222233334444:event-bus/auto-remediation"
      name = "auto-remediation"
    }
  }

  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:eu-central-1:222233334444:rule/auto-remediation/forwarded-authorize-security-group-ingress"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::222233334444:role/auto-remediate-open-ssh-lambda"
    }
  }
}

variables {
  organization_id = "o-abcde12345"
  alert_topic_arn = "arn:aws:sns:eu-central-1:222233334444:security-alerts-alerts"
}

run "central_bus_only_accepts_this_organization" {
  # apply, not plan: aws_cloudwatch_event_bus_policy.policy is Optional+Computed.
  command = apply

  assert {
    condition     = jsondecode(aws_cloudwatch_event_bus_policy.central.policy).Statement[0].Condition.StringEquals["aws:PrincipalOrgID"] == "o-abcde12345"
    error_message = "The central bus must only accept PutEvents from this organization."
  }
}

run "rule_matches_authorize_security_group_ingress_on_the_central_bus" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_rule.authorize_security_group_ingress.event_bus_name == aws_cloudwatch_event_bus.central.name
    error_message = "The rule must be on the central bus, not the account's default bus."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.authorize_security_group_ingress.event_pattern).detail.eventName == ["AuthorizeSecurityGroupIngress"]
    error_message = "The rule must match AuthorizeSecurityGroupIngress."
  }
}

run "lambda_can_assume_the_remediation_role_in_any_account_and_publish_to_the_given_topic" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role_policy.lambda.policy).Statement[1].Resource == "arn:aws:iam::*:role/security-remediation"
    error_message = "The Lambda role must be allowed to assume security-remediation in ANY account (the account id is not known here)."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.lambda.policy).Statement[2].Resource == "arn:aws:sns:eu-central-1:222233334444:security-alerts-alerts"
    error_message = "The Lambda role must be scoped to publish only to the given alert topic."
  }
}

run "lambda_environment_points_at_the_right_role_name_and_topic" {
  command = plan

  assert {
    condition     = aws_lambda_function.remediate_open_ssh.environment[0].variables["REMEDIATION_ROLE_NAME"] == "security-remediation"
    error_message = "The default remediation role name must be security-remediation."
  }

  assert {
    condition     = aws_lambda_function.remediate_open_ssh.environment[0].variables["ALERT_TOPIC_ARN"] == var.alert_topic_arn
    error_message = "The Lambda must be told the real alert topic ARN."
  }

  assert {
    condition     = aws_lambda_function.remediate_open_ssh.timeout <= 30
    error_message = "The default timeout must stay well under 30s (the whole point of this Lambda)."
  }
}

run "placeholder_organization_id_is_rejected" {
  command = plan

  variables {
    organization_id = "o-0000000000"
  }

  expect_failures = [var.organization_id]
}

run "bad_alert_topic_arn_is_rejected" {
  command = plan

  variables {
    alert_topic_arn = "not-an-arn"
  }

  expect_failures = [var.alert_topic_arn]
}
