include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/governance/data-perimeter.hcl"
  expose = true
}

# Resource Control Policies (S3, KMS, SQS, Secrets Manager by default). Apply AFTER governance/organization
# (RESOURCE_CONTROL_POLICY must already be an enabled policy type there, which it is by default) and after
# the real organization id and Policy-Staging OU id are filled in. See the module README, especially before
# ever adding "sts" to enabled_services.
inputs = {}
