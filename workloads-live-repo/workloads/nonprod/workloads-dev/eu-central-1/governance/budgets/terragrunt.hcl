include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/governance/budgets.hcl"
  expose = true
}

# Monthly budget and cost-anomaly monitor for this account. The amount and the alert address come
# from foundation-live-repo/_config/accounts.hcl (monthly_budget_usd, email).
inputs = {}
