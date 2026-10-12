# The data perimeter (PLAN 4.6): Resource Control Policies for S3, KMS, SQS and Secrets Manager, applied from the management account by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/governance/data-perimeter"
}

# Apply AFTER governance/organization (RESOURCE_CONTROL_POLICY must already be an enabled policy type there,
# which it is by default) and after the real organization id and Policy-Staging OU id are filled in. See the
# module README, especially before ever adding "sts" to enabled_services (sts is opt-in).
inputs = {
  organization_id = include.root.locals.organization.organization_id

  # TODO(owner): replace with the real Policy-Staging OU id once governance/organization is applied and
  # imported (same placeholder-OU-id situation as bootstrap-stacksets; look it up the same way, or read it
  # from governance/organization's organizational_unit_ids output). The module refuses to attach to an OU
  # that is not a key of this map.
  target_ou_ids = {
    "Policy-Staging" = "ou-0000-00000000"
  }

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
