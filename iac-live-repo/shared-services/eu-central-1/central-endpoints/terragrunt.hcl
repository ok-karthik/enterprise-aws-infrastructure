# The shared interface endpoints (PLAN 5.4), applied in shared-services by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/network/central-endpoints"
}

# Order of the first rollout (owner):
#   1. the shared-services account exists and has a real id in iac-live-repo/_config/accounts.hcl,
#   2. then apply this stack,
#   3. once a workload account and its VPC exist, add it to spoke_vpcs (below) and re-apply, then create the
#      matching aws_route53_zone_association in that workload account (not built by this stack; see the
#      module README).
locals {
  aws_region = include.root.locals.aws_region
}

inputs = {
  vpc_cidr            = "172.16.16.0/24" # distinct from IPAM's 10.0.0.0/8 and inspection-egress's 172.16.0.0/20
  azs                 = ["${local.aws_region}a", "${local.aws_region}b"]
  allowed_cidr_blocks = ["10.0.0.0/8"] # the platform's whole IPAM address space (network/ipam): every spoke VPC, without listing each one

  # TODO(owner): once workload accounts exist and their VPC ids/regions are known, list them here so their
  # zone associations can be authorized. Empty means no spoke is authorized yet (each service's zone is
  # created and usable from THIS account only).
  spoke_vpcs = []

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
