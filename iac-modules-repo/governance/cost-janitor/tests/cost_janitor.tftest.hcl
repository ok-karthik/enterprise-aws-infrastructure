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
      arn           = "arn:aws:lambda:eu-central-1:222233334444:function:cost-janitor"
      function_name = "cost-janitor"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::222233334444:role/cost-janitor-lambda"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-central-1:222233334444:log-group:/aws/lambda/cost-janitor"
    }
  }
}

run "default_plan_has_no_delete_permission" {
  # apply, not plan: the policy embeds the log group ARN, which is known only after apply (mock provider).
  command = apply

  assert {
    condition     = !strcontains(aws_iam_role_policy.lambda.policy, "ec2:DeleteVolume") && !strcontains(aws_iam_role_policy.lambda.policy, "ec2:DeleteSnapshot") && !strcontains(aws_iam_role_policy.lambda.policy, "ec2:ReleaseAddress") && !strcontains(aws_iam_role_policy.lambda.policy, "logs:PutRetentionPolicy")
    error_message = "In dry run mode the Lambda role must not be allowed to delete or change anything."
  }

  assert {
    condition     = length(aws_iam_role_policy.act) == 0
    error_message = "The act policy does not exist in dry run mode."
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables["DRY_RUN"] == "true"
    error_message = "The Lambda must default to dry run."
  }
}

run "act_mode_deletes_only_what_is_not_tagged_keep" {
  # apply, not plan: the policy embeds the log group ARN, which is known only after apply (mock provider).
  command = apply

  variables {
    dry_run = false
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.act[0].policy, "ec2:DeleteVolume") && strcontains(aws_iam_role_policy.act[0].policy, "aws:ResourceTag/keep")
    error_message = "Act mode adds the delete statements, conditioned on the keep tag."
  }

  assert {
    condition     = length(regexall("StringNotEqualsIgnoreCase", aws_iam_role_policy.act[0].policy)) == 3
    error_message = "The keep condition is case-insensitive, like is_kept in the code."
  }

  assert {
    condition     = length(regexall("aws:ResourceTag/keep", aws_iam_role_policy.act[0].policy)) == 3
    error_message = "Volumes, snapshots and Elastic IPs each carry the keep condition."
  }
}

run "alert_topic_adds_publish_permission_only_when_set" {
  # apply, not plan: the policy embeds the log group ARN, which is known only after apply (mock provider).
  command = apply

  variables {
    alert_topic_arn = "arn:aws:sns:eu-central-1:222233334444:alerts"
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.lambda.policy, "sns:Publish")
    error_message = "sns:Publish is allowed on the given topic."
  }
}

run "invalid_log_retention_is_rejected" {
  command = plan

  variables {
    default_log_retention_days = 31
  }

  expect_failures = [var.default_log_retention_days]
}
