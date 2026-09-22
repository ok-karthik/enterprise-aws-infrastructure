include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/security/org-cloudtrail.hcl"
  expose = true
}

# The organization trail. Apply AFTER security/log-archive's first apply (its bucket policy must already
# accept this trail's name) and after the log-archive account id and organization id are real
# (_config/accounts.hcl, _config/organization.hcl). See the module README for the naming contract.
inputs = {}
