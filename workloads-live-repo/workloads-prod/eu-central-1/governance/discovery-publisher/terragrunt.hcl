include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/governance/discovery-publisher.hcl"
  expose = true
}

# Publishes the VPC and EKS discovery parameters for this account. ack/cross_account_role_arn is added
# here once an ack-cross-account stack exists in the account.
inputs = {}
