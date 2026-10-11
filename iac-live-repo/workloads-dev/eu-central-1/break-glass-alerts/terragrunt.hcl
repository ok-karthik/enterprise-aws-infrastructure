# Break-glass alerts (PLAN 3.3): an EventBridge rule per sign-in path for the BreakGlassAdmin permission set, an encrypted SNS topic and email subscriptions. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/security/break-glass-alerts"
}

# Tells the account's email address about every BreakGlassAdmin sign-in (docs/IDENTITY.md).
# Verify the rules with a real sign-in during the break-glass drill: the event field names come from
# CloudTrail and are worth confirming once.
inputs = {
  # Alerts go to the account's root email from the registry. The module refuses @example.com, so a
  # placeholder fails at plan time instead of alerting nobody. Each address must confirm the SNS
  # subscription once (a confirmation email arrives after the first apply).
  notification_emails = [include.root.locals.account.email]

  # Only the management account sees the Identity Center portal calls (Federate / GetRoleCredentials).
  enable_sso_portal_rule = include.root.locals.account_name == "management"

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
