# Central security alerting (PLAN 4.5): EventBridge rules plus an encrypted SNS topic. Applied by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/security/security-alerts"
}

# Root sign-in / root API call and Organizations policy-change alerts (this is the management account).
# Confirm the SNS subscription in the account's email inbox after the first apply.
# Which rules are enabled depends on the account (see the module README): security-tooling gets the
# GuardDuty/Security Hub rules (it is the delegated administrator, PLAN 4.4); management gets the root
# sign-in and SCP-change rules (root credentials and Organizations only exist there).
inputs = {
  notification_emails = [include.root.locals.account.email]

  enable_guardduty_findings   = include.root.locals.account_name == "security-tooling"
  enable_securityhub_findings = include.root.locals.account_name == "security-tooling"
  enable_root_sign_in         = include.root.locals.account_name == "management"
  enable_scp_changes          = include.root.locals.account_name == "management"

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
