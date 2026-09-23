include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/security/security-alerts.hcl"
  expose = true
}

# GuardDuty and Security Hub finding alerts (this is the security-tooling account, the delegated
# administrator, PLAN 4.4). Confirm the SNS subscription in the account's email inbox after the first apply.
inputs = {}
