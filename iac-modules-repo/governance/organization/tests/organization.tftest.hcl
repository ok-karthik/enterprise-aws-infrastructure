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
    condition     = toset([for k, v in aws_organizations_policy_attachment.guardrails : split("/", k)[1]]) == toset(["Policy-Staging"])
    error_message = "By default every generic guardrail attaches to Policy-Staging only."
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.guardrails) == 8
    error_message = "8 generic guardrails x 1 OU (Policy-Staging) = 8 attachments: deny_leave_org, deny_disable_cloudtrail, deny_root_user_actions, deny_disable_detection_services, deny_iam_user_creation, protect_platform_resources, require_imdsv2, deny_role_creation_without_boundary."
  }

  assert {
    condition     = length(aws_organizations_policy.deny_unapproved_regions) == 0
    error_message = "The per-OU region SCP starts empty (allowed_regions_by_ou defaults to {}): nothing attaches until a caller opts an OU in."
  }
}

run "guardrails_can_be_widened" {
  command = plan

  variables {
    guardrail_target_ous = ["Policy-Staging", "Sandbox"]
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.guardrails) == 16
    error_message = "8 generic guardrails x 2 OUs = 16 attachments."
  }
}

run "region_scp_is_per_ou_and_only_for_ous_with_a_non_empty_list" {
  command = plan

  variables {
    allowed_regions_by_ou = {
      "Policy-Staging" = ["eu-central-1"]
      "Prod"           = ["eu-central-1", "eu-west-1"]
      "Suspended"      = []
    }
  }

  assert {
    condition     = toset(keys(aws_organizations_policy.deny_unapproved_regions)) == toset(["Policy-Staging", "Prod"])
    error_message = "Suspended has an empty list and must get no region SCP; every other listed OU gets its own."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.deny_unapproved_regions["Prod"].content).Statement[0].Condition.StringNotEquals["aws:RequestedRegion"] == ["eu-central-1", "eu-west-1"]
    error_message = "Each OU's SCP must deny every region outside its own list."
  }

  assert {
    condition     = toset(keys(aws_organizations_policy_attachment.deny_unapproved_regions)) == toset(["Policy-Staging", "Prod"])
    error_message = "Each listed OU must get exactly one region SCP attachment, keyed by that OU's own name."
  }

  assert {
    condition = alltrue([
      for a in ["budgets:*", "ce:*", "globalaccelerator:*", "health:*", "trustedadvisor:*", "waf:*", "shield:*", "account:*", "billing:*", "pricing:*", "route53domains:*", "iam:*", "organizations:*", "route53:*", "cloudfront:*", "support:*", "sts:*"] :
      contains(jsondecode(aws_organizations_policy.deny_unapproved_regions["Prod"].content).Statement[0].NotAction, a)
    ])
    error_message = "Global services must stay exempt from every region SCP."
  }
}

run "sandbox_guardrails_are_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_organizations_policy.sandbox_guardrails) == 0 && length(aws_organizations_policy_attachment.sandbox_guardrails) == 0
    error_message = "enable_sandbox_guardrails defaults to false."
  }

  assert {
    condition     = output.sandbox_guardrails_policy_id == null
    error_message = "The output must be null when the guardrails are off."
  }
}

run "sandbox_guardrails_deny_large_instances_and_reservation_purchases" {
  # apply, not plan: aws_organizations_policy_attachment.target_id is Optional+Computed, so the mock
  # provider leaves it unknown at plan time even though the config sets it explicitly.
  command = apply

  variables {
    enable_sandbox_guardrails = true
  }

  assert {
    condition     = one(aws_organizations_policy_attachment.sandbox_guardrails).target_id == aws_organizations_organizational_unit.top["Sandbox"].id
    error_message = "The Sandbox guardrails must attach only to the Sandbox OU."
  }

  assert {
    condition     = contains(jsondecode(one(aws_organizations_policy.sandbox_guardrails).content).Statement[0].Condition.StringLike["ec2:InstanceType"], "*.8xlarge")
    error_message = "Large instance families (8xlarge and up) must be denied."
  }

  assert {
    condition     = contains(jsondecode(one(aws_organizations_policy.sandbox_guardrails).content).Statement[1].Action, "ec2:PurchaseReservedInstancesOffering") && contains(jsondecode(one(aws_organizations_policy.sandbox_guardrails).content).Statement[1].Action, "savingsplans:CreateSavingsPlan")
    error_message = "Reserved Instance and Savings Plan purchases must be denied."
  }
}

run "suspended_deny_all_is_on_by_default_and_scoped_to_suspended_only" {
  # apply, not plan: same Optional+Computed target_id reason as above.
  command = apply

  assert {
    condition     = length(aws_organizations_policy.suspended_deny_all) == 1
    error_message = "enable_suspended_deny_all defaults to true."
  }

  assert {
    condition     = one(aws_organizations_policy_attachment.suspended_deny_all).target_id == aws_organizations_organizational_unit.top["Suspended"].id
    error_message = "The deny-all SCP must attach only to the Suspended OU."
  }

  assert {
    condition     = jsondecode(one(aws_organizations_policy.suspended_deny_all).content).Statement[0] == { Sid = "DenyEverything", Effect = "Deny", Action = "*", Resource = "*" }
    error_message = "The Suspended OU policy must deny every action on every resource, with no exception."
  }
}

run "deny_iam_user_creation_exempts_only_break_glass" {
  command = plan

  assert {
    condition     = jsondecode(aws_organizations_policy.deny_iam_user_creation.content).Statement[0].Condition.StringNotLike["aws:PrincipalArn"] == ["arn:*:sts::*:assumed-role/AWSReservedSSO_BreakGlassAdmin_*/*"]
    error_message = "Only a BreakGlassAdmin session may create IAM users, login profiles or access keys."
  }

  assert {
    condition     = toset(jsondecode(aws_organizations_policy.deny_iam_user_creation.content).Statement[0].Action) == toset(["iam:CreateUser", "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "iam:CreateAccessKey"])
    error_message = "The IAM-user guardrail must cover users, login profiles and access keys."
  }
}

run "protect_platform_resources_exempts_stacksets_and_break_glass" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(aws_organizations_policy.protect_platform_resources.content).Statement :
      toset(s.Condition.StringNotLike["aws:PrincipalArn"]) == toset([
        "arn:*:sts::*:assumed-role/AWSServiceRoleForCloudFormationStackSetsOrgMember/*",
        "arn:*:sts::*:assumed-role/AWSReservedSSO_BreakGlassAdmin_*/*",
      ])
    ])
    error_message = "Every statement must exempt exactly the StackSets service-linked role and BreakGlassAdmin, and no one else."
  }

  assert {
    condition     = contains(jsondecode(aws_organizations_policy.protect_platform_resources.content).Statement[0].Resource, "arn:*:iam::*:role/platform-*") && contains(jsondecode(aws_organizations_policy.protect_platform_resources.content).Statement[0].Resource, "arn:*:iam::*:role/github-actions-*")
    error_message = "Both platform-* and github-actions-* roles must be protected."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.protect_platform_resources.content).Statement[1].Resource == "arn:*:iam::*:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The GitHub OIDC provider must be protected."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.protect_platform_resources.content).Statement[2].Resource == "arn:*:s3:::tg-state-*"
    error_message = "The tg-state-* buckets must be protected."
  }
}

run "require_imdsv2_denies_run_instances_without_it" {
  command = plan

  assert {
    # checkov:skip=CKV_SECRET_6: not a secret, an IAM condition key/value pair (false positive on this string's entropy)
    condition     = jsondecode(aws_organizations_policy.require_imdsv2.content).Statement[0].Condition.StringNotEquals["ec2:MetadataHttpTokens"] == "required"
    error_message = "ec2:RunInstances must be denied unless IMDSv2 is required."
  }
}

run "deny_role_creation_without_boundary_matches_the_account_baseline_boundary_name" {
  command = plan

  assert {
    condition     = jsondecode(aws_organizations_policy.deny_role_creation_without_boundary.content).Statement[0].Condition.StringNotEquals["iam:PermissionsBoundary"] == "arn:*:iam::*:policy/platform-workload-boundary"
    error_message = "The boundary name here must match account-baseline's boundary_name exactly (platform-workload-boundary), or a real role creation would not be recognized as compliant."
  }
}

run "deny_root_user_matches_the_literal_root_arn_not_a_break_glass_session" {
  command = plan

  assert {
    condition     = jsondecode(aws_organizations_policy.deny_root_user_actions.content).Statement[0].Condition.StringLike["aws:PrincipalArn"] == "arn:*:iam::*:root"
    error_message = "Root must be matched by the classic :root ARN, which sts:AssumeRoot sessions do not use (docs/ROOT_ACCESS.md)."
  }
}

run "custom_break_glass_pattern_must_be_an_assumed_role_arn" {
  command = plan

  variables {
    break_glass_role_arn_pattern = "arn:aws:iam::123456789012:role/SomeRole"
  }

  expect_failures = [var.break_glass_role_arn_pattern]
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
