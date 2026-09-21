include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/governance/account-factory.hcl"
  expose = true
}

# Applied by the owner from the management account, never by CI. Apply the organization stack first.
#
# The module refuses to plan while an account in foundation-live-repo/_config/accounts.hcl that has
# create = true still has a placeholder (@example.com) email. Fill in the real emails first.
#
# Accounts you already created by hand (log-archive, security-tooling, the workload account) must be
# IMPORTED, or Terraform tries to create them again:
#   terragrunt import 'aws_organizations_account.this["log-archive"]' <12-digit-account-id>
# and then make sure the account sits in the OU named in the registry (the plan shows a parent_id change if not).
# Accounts are never closed by Terraform (prevent_destroy, close_on_deletion = false).
inputs = {}
