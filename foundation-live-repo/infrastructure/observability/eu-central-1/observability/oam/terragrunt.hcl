include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/observability/oam.hcl"
  expose = true
}

# The OAM sink of the platform. Prerequisites:
#   1. The observability account exists with a real id in _config/accounts.hcl and observability/account.hcl.
#   2. The real organization id is in _config/organization.hcl (the sink refuses the placeholder).
#   3. Apply this leaf, then paste the `sink_arn` output into each source account's account-baseline
#      (observability_sink_arn), in the same region. Set enable_prometheus = true here to add a Managed
#      Prometheus workspace (costs per ingested sample).
inputs = {}
