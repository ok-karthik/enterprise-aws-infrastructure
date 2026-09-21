# Member-account Day-0 bootstrap: deploys the same template as the management account's
# platform-bootstrap stack (foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml) to
# every account in the targeted OUs, with no human step when a new account joins.
#
# Requires: AWS Organizations with all features, and StackSets trusted access enabled
# (bootstrap.sh does both). Applied from the management account.

resource "aws_cloudformation_stack_set" "this" {
  for_each = var.stack_sets

  name             = each.key
  description      = "Day-0 bootstrap (state bucket, GitHub OIDC, CI roles) for accounts whose GitHub Environment is ${each.value.github_environment}"
  permission_model = "SERVICE_MANAGED"
  call_as          = "SELF"
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = var.template_body

  parameters = {
    GitHubRepo            = var.github_repo
    GitHubEnvironment     = each.value.github_environment
    NoncurrentVersionDays = tostring(var.noncurrent_version_days)
    # Fixed, never a variable: member accounts must never be allowed to manage Organizations.
    # The permissions boundary then denies organizations:* and account:* there.
    AllowOrganizationsAdmin = "false"
    # Same for IAM Identity Center: only the management account's bootstrap stack allows the apply role to
    # manage it (bootstrap.sh). The boundary then denies sso:*, sso-directory:* and identitystore:* here.
    AllowIdentityCenterAdmin = "false"
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = true
  }

  operation_preferences {
    max_concurrent_percentage = 25
    failure_tolerance_count   = 0
  }

  tags = var.tags

  lifecycle {
    # The provider reports an administration role for SERVICE_MANAGED sets; it is not used.
    ignore_changes = [administration_role_arn]
  }
}

resource "aws_cloudformation_stack_set_instance" "this" {
  for_each = var.stack_sets

  stack_set_name            = aws_cloudformation_stack_set.this[each.key].name
  call_as                   = "SELF"
  stack_set_instance_region = var.region

  # Never delete a member account's stack (and with it the roles CI depends on) because
  # this instance was removed from Terraform.
  retain_stack = true

  deployment_targets {
    organizational_unit_ids = each.value.organizational_unit_ids
  }
}
