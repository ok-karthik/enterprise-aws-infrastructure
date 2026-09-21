include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/network/vpc.hcl"
  expose = true
}

# No changes needed to local variables as they are inherited,
# but CIDR is specific to this region.
inputs = {
  cidr             = "10.0.0.0/16"
  database_subnets = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
}
