# Budgets (PLAN 2.8): a monthly cost budget per account plus Cost Anomaly Detection. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/governance/budgets"
}

# Monthly budget and cost-anomaly monitor for this account: alerts at 50 / 80 / 100 % actual and 100 % forecast.
# The amount and the alert address come from iac-live-repo/_config/accounts.hcl (monthly_budget_usd, email).
inputs = {
  account_name  = include.root.locals.account_name
  monthly_limit = include.root.locals.account.monthly_budget_usd

  # Alerts go to the account's root email from the registry. The module refuses @example.com, so a
  # placeholder fails at plan time instead of alerting nobody.
  notification_emails = [include.root.locals.account.email]

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
