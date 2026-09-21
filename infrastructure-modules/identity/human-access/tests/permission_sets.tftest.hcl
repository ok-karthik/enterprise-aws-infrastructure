# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_resource "aws_ssoadmin_permission_set" {
    defaults = {
      arn = "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef"
    }
  }
}

variables {
  sso_instance_arn = "arn:aws:sso:::instance/ssoins-1234567890abcdef"
}

run "platform_engineer_has_no_standing_admin" {
  command = apply

  assert {
    condition     = aws_ssoadmin_managed_policy_attachment.platform_engineer_power_user[0].managed_policy_arn == "arn:aws:iam::aws:policy/PowerUserAccess"
    error_message = "PlatformEngineer must use PowerUserAccess, not AdministratorAccess."
  }

  assert {
    condition     = endswith(aws_ssoadmin_permission_set.platform_engineer[0].name, "-PlatformEngineer")
    error_message = "The permission set must be named PlatformEngineer."
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_ssoadmin_permission_set_inline_policy.platform_engineer_iam[0].inline_policy).Statement : s.Effect == "Deny" || length(regexall("role/platform/\\*", jsonencode(s.Resource))) > 0])
    error_message = "Every Allow statement in the inline policy must be limited to role/platform/*."
  }

  assert {
    condition     = strcontains(aws_ssoadmin_permission_set_inline_policy.platform_engineer_iam[0].inline_policy, "DenyAdminPolicyAttachment")
    error_message = "PlatformEngineer must not be able to attach AdministratorAccess to a platform role."
  }
}

run "break_glass_is_short_lived" {
  command = apply

  assert {
    condition     = aws_ssoadmin_permission_set.break_glass[0].session_duration == "PT1H"
    error_message = "BreakGlassAdmin sessions must default to 1 hour."
  }

  assert {
    condition     = aws_ssoadmin_managed_policy_attachment.break_glass_admin[0].managed_policy_arn == "arn:aws:iam::aws:policy/AdministratorAccess"
    error_message = "BreakGlassAdmin carries AdministratorAccess."
  }
}

run "break_glass_session_cannot_be_long" {
  command = plan

  variables {
    break_glass_session_duration = "PT8H"
  }

  expect_failures = [var.break_glass_session_duration]
}
