include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/security/log-archive.hcl"
  expose = true
}

# The central log archive. Order of the first rollout (owner):
#   1. the log-archive account exists and has a real id in _config/accounts.hcl and log-archive/account.hcl,
#   2. the real organization id is in _config/organization.hcl,
#   3. the Day-0 bootstrap stack ran in the account (state bucket), then apply this leaf,
#   4. copy `kms_key_arn` from the output into foundation-live-repo/_config/organization.hcl (log_archive_kms_key_arn),
#      which the org-cloudtrail leaf in the management account reads.
# COMPLIANCE Object Lock cannot be undone. Read the module README before the first apply.
inputs = {}
