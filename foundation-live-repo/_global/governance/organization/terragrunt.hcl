include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/governance/organization.hcl"
  expose = true
}

inputs = {
  root_id = "" # Can be supplied via var or pipeline environment
}
