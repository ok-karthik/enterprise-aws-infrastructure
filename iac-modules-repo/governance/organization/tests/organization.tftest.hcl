# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_resource "aws_organizations_organization" {
    defaults = {
      id                = "o-abcd123456"
      master_account_id = "111122223333"
      roots             = [{ id = "r-ab12", arn = "arn:aws:organizations::111122223333:root/o-abcd123456/r-ab12", name = "Root", policy_types = [] }]
    }
  }

  mock_resource "aws_organizations_organizational_unit" {
    defaults = {
      id = "ou-ab12-cd34ef56"
    }
  }

  mock_resource "aws_organizations_policy" {
    defaults = {
      id = "p-ab12cd34"
    }
  }
}

run "default_tree_matches_the_plan_layout" {
  command = plan

  assert {
    condition     = toset(keys(aws_organizations_organizational_unit.top)) == toset(["Security", "Infrastructure", "Workloads", "Sandbox", "Policy-Staging", "Suspended"])
    error_message = "Top-level OUs must be Security, Infrastructure, Workloads, Sandbox, Policy-Staging, Suspended."
  }

  assert {
    condition     = toset(keys(aws_organizations_organizational_unit.child)) == toset(["Prod", "NonProd"])
    error_message = "Workloads must have Prod and NonProd below it."
  }
}

run "organization_keeps_stacksets_access_and_all_policy_types" {
  command = plan

  assert {
    condition     = contains(aws_organizations_organization.this.aws_service_access_principals, "member.org.stacksets.cloudformation.amazonaws.com")
    error_message = "StackSets trusted access must stay enabled, or the bootstrap StackSets stop working."
  }

  assert {
    condition     = toset(aws_organizations_organization.this.enabled_policy_types) == toset(["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY", "TAG_POLICY", "BACKUP_POLICY", "DECLARATIVE_POLICY_EC2"])
    error_message = "All five policy types must be enabled."
  }

  assert {
    condition     = aws_organizations_organization.this.feature_set == "ALL"
    error_message = "The organization needs all features."
  }
}

run "guardrails_start_on_policy_staging_only" {
  command = plan

  assert {
    condition     = toset(keys(aws_organizations_policy_attachment.guardrails)) == toset(["deny_leave_org/Policy-Staging", "deny_disable_cloudtrail/Policy-Staging", "deny_unapproved_regions/Policy-Staging"])
    error_message = "By default every guardrail attaches to Policy-Staging only."
  }
}

run "guardrails_can_be_widened" {
  command = plan

  variables {
    guardrail_target_ous = ["Policy-Staging", "Sandbox"]
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.guardrails) == 6
    error_message = "3 guardrails x 2 OUs = 6 attachments."
  }
}

run "region_scp_uses_allowed_regions" {
  command = plan

  variables {
    allowed_regions = ["eu-central-1", "eu-west-1"]
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.deny_unapproved_regions.content).Statement[0].Condition.StringNotEquals["aws:RequestedRegion"] == ["eu-central-1", "eu-west-1"]
    error_message = "SCP must deny every region outside var.allowed_regions."
  }

  assert {
    condition = alltrue([
      for a in ["budgets:*", "ce:*", "globalaccelerator:*", "health:*", "trustedadvisor:*", "waf:*", "shield:*", "account:*", "billing:*", "pricing:*", "route53domains:*", "iam:*", "organizations:*", "route53:*", "cloudfront:*", "support:*", "sts:*"] :
      contains(jsondecode(aws_organizations_policy.deny_unapproved_regions.content).Statement[0].NotAction, a)
    ])
    error_message = "Global services must stay exempt from the region SCP."
  }
}

run "empty_region_list_is_rejected" {
  command = plan

  variables {
    allowed_regions = []
  }

  expect_failures = [var.allowed_regions]
}

run "parent_must_be_a_top_level_ou" {
  command = plan

  variables {
    organizational_units = {
      "A" = {}
      "B" = { parent = "A" }
      "C" = { parent = "B" }
    }
    guardrail_target_ous = []
  }

  expect_failures = [var.organizational_units]
}

run "unknown_parent_is_rejected" {
  command = plan

  variables {
    organizational_units = {
      "B" = { parent = "Nope" }
    }
    guardrail_target_ous = []
  }

  expect_failures = [var.organizational_units]
}

run "scp_policy_type_is_required" {
  command = plan

  variables {
    enabled_policy_types = ["TAG_POLICY"]
  }

  expect_failures = [var.enabled_policy_types]
}

run "centralized_root_access_is_on_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_organizations_features.this) == 1 && toset(aws_iam_organizations_features.this[0].enabled_features) == toset(["RootCredentialsManagement", "RootSessions"])
    error_message = "Both root access features must be enabled."
  }
}

run "centralized_root_access_can_be_switched_off" {
  command = plan

  variables {
    enable_centralized_root_access = false
  }

  assert {
    condition     = length(aws_iam_organizations_features.this) == 0
    error_message = "enable_centralized_root_access = false creates nothing."
  }
}

run "root_access_needs_iam_trusted_access" {
  command = plan

  variables {
    aws_service_access_principals = ["member.org.stacksets.cloudformation.amazonaws.com"]
  }

  expect_failures = [aws_iam_organizations_features.this]
}

run "delegated_administrator_is_registered" {
  command = plan

  variables {
    delegated_administrators = { "access-analyzer.amazonaws.com" = "222222222222" }
  }

  assert {
    condition     = aws_organizations_delegated_administrator.this["access-analyzer.amazonaws.com"].account_id == "222222222222"
    error_message = "The account must be registered as delegated administrator of the service."
  }
}

run "delegated_administrator_placeholder_is_rejected" {
  command = plan

  variables {
    delegated_administrators = { "access-analyzer.amazonaws.com" = "000000000002" }
  }

  expect_failures = [var.delegated_administrators]
}

run "delegated_service_needs_trusted_access" {
  command = plan

  variables {
    delegated_administrators      = { "guardduty.amazonaws.com" = "222222222222" }
    aws_service_access_principals = ["iam.amazonaws.com"]
  }

  expect_failures = [var.delegated_administrators]
}
