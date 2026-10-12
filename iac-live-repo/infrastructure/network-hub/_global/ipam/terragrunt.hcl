# The org-wide IPAM (PLAN 5.1), applied in network-hub by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/network/ipam"
}

# Order of the first rollout (owner):
#   1. the network-hub account exists and has a real id in iac-live-repo/_config/accounts.hcl,
#   2. the real organization id is in _config/organization.hcl and the real Workloads OU id is filled in here,
#   3. turn on RAM sharing with AWS Organizations for the whole org (aws_ram_sharing_with_organization) --
#      a one-time, org-wide setting, not created by this module,
#   4. then apply this stack.
inputs = {
  organization_id = include.root.locals.organization.organization_id

  # TODO(owner): replace with the real Workloads OU ARN once governance/organization is applied and imported
  # (arn:aws:organizations::<management account id>:ou/<org id>/<workloads ou id>). The module refuses to
  # plan while this is not a well-formed OU ARN.
  workloads_ou_arn = "arn:aws:organizations::000000000000:ou/o-0000000000/ou-0000-00000000"

  operating_regions = [include.root.locals.regions.primary_region, include.root.locals.regions.secondary_region]

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
