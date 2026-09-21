# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-1234567890abcdef"]
      identity_store_ids = ["d-1234567890"]
    }
  }

  mock_data "aws_identitystore_group" {
    defaults = {
      group_id = "11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_ssoadmin_permission_set" {
    defaults = {
      arn = "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef"
    }
  }

  mock_resource "aws_identitystore_group" {
    defaults = {
      group_id = "99999999-2222-3333-4444-555555555555"
    }
  }
}

variables {
  groups = ["developers", "platform-engineers", "security-auditors"]
  accounts = {
    management     = { id = "954171757349", ou = "Root" }
    workloads-dev  = { id = "222222222222", ou = "NonProd" }
    workloads-prod = { id = "333333333333", ou = "Prod" }
  }
  assignments = {
    NonProd = { developers = ["Developer"], "platform-engineers" = ["PlatformEngineer"] }
    Prod    = { developers = ["ReadOnly"], "security-auditors" = ["SecurityAudit"] }
    Root    = { "platform-engineers" = ["ReadOnly"] }
  }
}

run "catalog_and_sessions" {
  command = plan

  assert {
    condition     = toset(keys(aws_ssoadmin_permission_set.this)) == toset(["ReadOnly", "Developer", "PlatformEngineer", "SecurityAudit", "Billing", "BreakGlassAdmin"])
    error_message = "The catalog is ReadOnly, Developer, PlatformEngineer, SecurityAudit, Billing and BreakGlassAdmin."
  }

  assert {
    condition     = aws_ssoadmin_permission_set.this["BreakGlassAdmin"].session_duration == "PT1H" && aws_ssoadmin_permission_set.this["PlatformEngineer"].session_duration == "PT1H"
    error_message = "Elevated sets get 1-hour sessions."
  }

  assert {
    condition     = alltrue([for n in ["ReadOnly", "Developer", "SecurityAudit", "Billing"] : aws_ssoadmin_permission_set.this[n].session_duration == "PT8H"])
    error_message = "Everything else gets 8-hour sessions."
  }
}

run "no_standing_admin_except_break_glass" {
  command = plan

  assert {
    condition     = length([for k, a in aws_ssoadmin_managed_policy_attachment.this : k if endswith(a.managed_policy_arn, "/AdministratorAccess")]) == 1 && aws_ssoadmin_managed_policy_attachment.this["BreakGlassAdmin/AdministratorAccess"].managed_policy_arn == "arn:aws:iam::aws:policy/AdministratorAccess"
    error_message = "AdministratorAccess belongs to BreakGlassAdmin only."
  }

  assert {
    condition     = strcontains(aws_ssoadmin_permission_set_inline_policy.platform_engineer.inline_policy, "DenyAdminPolicyAttachment") && strcontains(aws_ssoadmin_permission_set_inline_policy.platform_engineer.inline_policy, "arn:aws:iam::*:policy/platform-workload-boundary")
    error_message = "PlatformEngineer cannot attach admin policies and can only create roles that carry the workload boundary."
  }
}

run "developer_uses_customer_policy_and_boundary_by_name" {
  command = plan

  assert {
    condition     = one(aws_ssoadmin_customer_managed_policy_attachment.developer.customer_managed_policy_reference).name == "platform-developer"
    error_message = "Developer attaches the platform-developer policy from the baseline."
  }

  assert {
    condition     = one(one(aws_ssoadmin_permissions_boundary_attachment.developer.permissions_boundary).customer_managed_policy_reference).name == "platform-workload-boundary"
    error_message = "Developer is capped by platform-workload-boundary."
  }
}

run "assignments_expand_by_ou_using_the_registry" {
  command = plan

  assert {
    condition = toset(keys(aws_ssoadmin_account_assignment.this)) == toset([
      "workloads-dev/developers/Developer",
      "workloads-dev/platform-engineers/PlatformEngineer",
      "workloads-prod/developers/ReadOnly",
      "workloads-prod/security-auditors/SecurityAudit",
      "management/platform-engineers/ReadOnly",
    ])
    error_message = "Each OU assignment must expand to exactly the accounts in that OU."
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this["workloads-dev/developers/Developer"].target_id == "222222222222" && aws_ssoadmin_account_assignment.this["workloads-dev/developers/Developer"].principal_type == "GROUP"
    error_message = "Assignments target the account id and use groups, never users."
  }
}

run "scim_groups_are_read_not_created" {
  command = plan

  assert {
    condition     = length(aws_identitystore_group.this) == 0 && length(data.aws_identitystore_group.scim) == 3
    error_message = "With an external IdP the groups are looked up."
  }
}

run "groups_can_be_created_without_an_idp" {
  command = plan

  variables {
    manage_groups = true
  }

  assert {
    condition     = length(aws_identitystore_group.this) == 3 && length(data.aws_identitystore_group.scim) == 0
    error_message = "manage_groups = true creates the groups."
  }
}

run "abac_session_tags_are_configured" {
  command = plan

  assert {
    condition     = length(aws_ssoadmin_instance_access_control_attributes.this) == 1 && toset([for a in aws_ssoadmin_instance_access_control_attributes.this[0].attribute : a.key]) == toset(["team", "cost_center"])
    error_message = "team and cost_center must become session tags."
  }
}

run "abac_can_be_switched_off" {
  command = plan

  variables {
    abac_attributes = {}
  }

  assert {
    condition     = length(aws_ssoadmin_instance_access_control_attributes.this) == 0
    error_message = "An empty map configures no attributes."
  }
}

run "break_glass_cannot_be_assigned_statically" {
  command = plan

  variables {
    assignments = { NonProd = { "platform-engineers" = ["BreakGlassAdmin"] } }
  }

  expect_failures = [var.assignments]
}

run "break_glass_exception_must_be_deliberate" {
  command = plan

  variables {
    assignments              = { NonProd = { "platform-engineers" = ["BreakGlassAdmin"] } }
    allow_static_break_glass = true
  }

  assert {
    condition     = contains(keys(aws_ssoadmin_account_assignment.this), "workloads-dev/platform-engineers/BreakGlassAdmin")
    error_message = "allow_static_break_glass = true is the explicit override."
  }
}

run "platform_engineer_in_prod_needs_jit" {
  command = plan

  variables {
    assignments = { Prod = { "platform-engineers" = ["PlatformEngineer"] } }
  }

  expect_failures = [var.assignments]
}

run "developer_in_prod_is_rejected" {
  command = plan

  variables {
    assignments = { Prod = { developers = ["Developer"] } }
  }

  expect_failures = [var.assignments]
}

run "unknown_permission_set_is_rejected" {
  command = plan

  variables {
    assignments = { NonProd = { developers = ["Admin"] } }
  }

  expect_failures = [var.assignments]
}

run "unknown_group_is_rejected" {
  command = plan

  variables {
    assignments = { NonProd = { "ghost-group" = ["ReadOnly"] } }
  }

  expect_failures = [var.assignments]
}

run "placeholder_account_id_is_rejected" {
  command = plan

  variables {
    accounts = { workloads-dev = { id = "000000000005", ou = "NonProd" } }
  }

  expect_failures = [var.accounts]
}

run "long_sessions_are_rejected" {
  command = plan

  variables {
    session_durations = {
      ReadOnly         = "PT24H"
      Developer        = "PT8H"
      PlatformEngineer = "PT1H"
      SecurityAudit    = "PT8H"
      Billing          = "PT8H"
      BreakGlassAdmin  = "PT1H"
    }
  }

  expect_failures = [var.session_durations]
}
