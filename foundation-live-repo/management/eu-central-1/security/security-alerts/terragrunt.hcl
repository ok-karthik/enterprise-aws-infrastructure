include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/security/security-alerts.hcl"
  expose = true
}

# Root sign-in / root API call and Organizations policy-change alerts (this is the management account).
# Confirm the SNS subscription in the account's email inbox after the first apply.
inputs = {}
