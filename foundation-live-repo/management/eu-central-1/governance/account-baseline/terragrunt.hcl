include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/governance/account-baseline.hcl"
  expose = true
}

# The account baseline: account alias, password policy, S3 Block Public Access, EBS encryption and IMDSv2
# defaults, the KMS keys, platform-workload-boundary and the account discovery parameters.
# The state bucket and the CI roles are NOT here: they come from the Day-0 bootstrap stack.
inputs = {}
