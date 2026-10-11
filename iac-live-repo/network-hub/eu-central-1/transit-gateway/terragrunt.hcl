# The transit gateway (PLAN 5.2), applied in network-hub, once per region, by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/network/transit-gateway"
}

# Order of the first rollout (owner): the network-hub account exists with a real id and the real
# Workloads/Infrastructure OU ARNs are filled in (below). Cross-region peering is applied afterwards, in
# ../tgw-peering (a separate stack that depends on both regional transit gateways). See the module README for
# accept_vpc_attachments (off through the first apply).
inputs = {
  # TODO(owner): replace with the real Workloads / Infrastructure OU ARNs once governance/organization is
  # applied and imported. The module refuses to plan while these are not well-formed OU ARNs.
  workloads_ou_arn      = "arn:aws:organizations::000000000000:ou/o-0000000000/ou-0000-00000000"
  infrastructure_ou_arn = "arn:aws:organizations::000000000000:ou/o-0000000000/ou-0000-11111111"

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
