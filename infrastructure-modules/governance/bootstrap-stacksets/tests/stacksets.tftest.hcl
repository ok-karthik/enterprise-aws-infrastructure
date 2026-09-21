# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

variables {
  template_body = "AWSTemplateFormatVersion: '2010-09-09'\nResources: {}\n"
  stack_sets = {
    bootstrap-nonprod = {
      github_environment      = "dev"
      organizational_unit_ids = ["ou-ab12-cd34ef56"]
    }
    bootstrap-prod = {
      github_environment      = "prod"
      organizational_unit_ids = ["ou-ab12-9z8y7x6w"]
    }
  }
}

run "member_accounts_can_never_manage_organizations" {
  command = plan

  assert {
    condition     = alltrue([for _, s in aws_cloudformation_stack_set.this : s.parameters["AllowOrganizationsAdmin"] == "false"])
    error_message = "Member StackSets must always pass AllowOrganizationsAdmin = \"false\"."
  }
}

run "each_stack_set_trusts_its_own_environment" {
  command = plan

  assert {
    condition     = aws_cloudformation_stack_set.this["bootstrap-nonprod"].parameters["GitHubEnvironment"] == "dev" && aws_cloudformation_stack_set.this["bootstrap-prod"].parameters["GitHubEnvironment"] == "prod"
    error_message = "The GitHub Environment (apply-role trust subject) must differ per StackSet."
  }
}

run "auto_deployment_retains_stacks_and_rolls_out_carefully" {
  command = plan

  assert {
    condition     = alltrue([for _, s in aws_cloudformation_stack_set.this : s.permission_model == "SERVICE_MANAGED" && s.auto_deployment[0].enabled && s.auto_deployment[0].retain_stacks_on_account_removal])
    error_message = "StackSets must be service-managed with auto-deployment on and retain-on-removal."
  }

  assert {
    condition     = alltrue([for _, s in aws_cloudformation_stack_set.this : s.operation_preferences[0].max_concurrent_percentage == 25 && s.operation_preferences[0].failure_tolerance_count == 0])
    error_message = "Rollouts must be 25% at a time with zero failure tolerance."
  }
}

run "instances_target_ous_in_one_region_and_are_retained" {
  command = plan

  assert {
    condition     = alltrue([for _, i in aws_cloudformation_stack_set_instance.this : i.stack_set_instance_region == "eu-central-1" && i.retain_stack])
    error_message = "Instances must be deployed to the primary region only, with retain_stack = true."
  }
}

run "name_must_start_with_bootstrap" {
  command = plan

  variables {
    stack_sets = {
      platform-member-bootstrap = {
        github_environment      = "dev"
        organizational_unit_ids = ["ou-ab12-cd34ef56"]
      }
    }
  }

  expect_failures = [var.stack_sets]
}

run "root_id_is_rejected" {
  command = plan

  variables {
    stack_sets = {
      bootstrap-nonprod = {
        github_environment      = "dev"
        organizational_unit_ids = ["r-ab12"]
      }
    }
  }

  expect_failures = [var.stack_sets]
}

run "empty_ou_list_is_rejected" {
  command = plan

  variables {
    stack_sets = {
      bootstrap-nonprod = {
        github_environment      = "dev"
        organizational_unit_ids = []
      }
    }
  }

  expect_failures = [var.stack_sets]
}

run "placeholder_ou_is_rejected" {
  command = plan

  variables {
    stack_sets = {
      bootstrap-nonprod = {
        github_environment      = "dev"
        organizational_unit_ids = ["ou-0000-00000000"]
      }
    }
  }

  expect_failures = [var.stack_sets]
}
