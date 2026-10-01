include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/governance/billing.hcl"
  expose = true
}

# CUR 2.0 export + cost anomaly monitors per OU. Prerequisites and order:
#   1. TODO(owner): a real email for the management account in _config/accounts.hcl (the module refuses @example.com).
#   2. Apply once as it is. Then, after resources tagged CostCenter have shown up in billing (up to 24 h), set
#        cost_allocation_tags = ["CostCenter"]
#      below and apply again (a tag key cannot be activated before AWS has seen it).
#   3. Nothing else is needed for Athena: point a table at s3://<cur_bucket_name>/cur2/ (see the module README).
inputs = {}
