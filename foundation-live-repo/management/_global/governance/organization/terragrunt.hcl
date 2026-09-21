include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/governance/organization.hcl"
  expose = true
}

# Applied by the owner from the management account, never by CI.
#
# BEFORE THE FIRST APPLY: the organization already exists (bootstrap.sh created it), so import it,
# otherwise Terraform tries to create a second one and fails. From this folder, logged in to the
# management account with an SSO profile:
#   terragrunt import 'aws_organizations_organization.this' <organization-id>     # o-..., from the console
# Then run `terragrunt plan` and READ IT: service access principals and policy types are authoritative,
# so anything enabled by hand and missing from the module defaults is shown as a removal.
# OUs you already created by hand are imported the same way, one per OU:
#   terragrunt import 'aws_organizations_organizational_unit.top["Sandbox"]' <ou-id>
# A plan that shows the OUs as "create" when they already exist means the import was skipped.
inputs = {}
