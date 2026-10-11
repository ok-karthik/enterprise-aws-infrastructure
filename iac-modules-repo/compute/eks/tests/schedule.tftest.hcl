# Offline unit tests (no AWS credentials): `terraform test` from this module directory.
# Covers the working-hours schedule (PLAN 9.5) and the ami_type / instance_types check.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
      arn        = "arn:aws:iam::111122223333:user/test"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
}

variables {
  cluster_name     = "test"
  vpc_id           = "vpc-12345678"
  subnet_ids       = ["subnet-12345678", "subnet-87654321"]
  enable_karpenter = false
}

run "default_has_no_schedule_resources" {
  command = plan

  assert {
    condition     = length(aws_scheduler_schedule.down) == 0 && length(aws_scheduler_schedule.up) == 0 && length(aws_iam_role.scheduler) == 0
    error_message = "No schedule resources unless scale_schedule is set."
  }

  assert {
    condition     = length(output.scale_schedule_names) == 0
    error_message = "scale_schedule_names is empty when the schedule is off."
  }
}

run "schedule_creates_two_schedules_and_one_role" {
  command = plan

  variables {
    scale_schedule = {}
    min_size       = 0
  }

  assert {
    condition     = length(aws_scheduler_schedule.down) == 1 && length(aws_scheduler_schedule.up) == 1 && length(aws_iam_role.scheduler) == 1
    error_message = "Two schedules and one role."
  }

  assert {
    condition     = aws_scheduler_schedule.down[0].schedule_expression_timezone == "Europe/Berlin" && aws_scheduler_schedule.up[0].schedule_expression == "cron(0 7 ? * MON-FRI *)"
    error_message = "Defaults are weekdays 07:00-19:00 Berlin."
  }
}

run "schedule_with_min_size_above_zero_is_rejected" {
  command = plan

  variables {
    scale_schedule = {}
    min_size       = 1
  }

  expect_failures = [var.scale_schedule]
}

run "arm_instances_with_x86_ami_are_rejected" {
  command = plan

  variables {
    instance_types = ["t4g.small"]
    ami_type       = "AL2023_x86_64_STANDARD"
  }

  expect_failures = [var.ami_type]
}

run "x86_instances_with_x86_ami_are_accepted" {
  command = plan

  variables {
    instance_types = ["m6i.large"]
    ami_type       = "AL2023_x86_64_STANDARD"
  }
}
