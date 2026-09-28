include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/network/vpc.hcl"
  expose = true
}

# Production VPC might use a different CIDR range to avoid overlapping with Dev
inputs = {
  cidr             = "10.1.0.0/16"
  private_subnets  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  public_subnets   = ["10.1.101.0/24"]
  database_subnets = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]
}
