# CloudWatch cross-account observability (PLAN 9.1): the SINK, in the observability account, applied by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/observability/oam"
}

# Every other account links to the sink through governance/account-baseline (observability_sink_arn). Prerequisites:
#   1. The observability account exists with a real id in iac-live-repo/_config/accounts.hcl.
#   2. The real organization id is in _config/organization.hcl (the sink refuses the placeholder).
#   3. Apply this stack, then paste the `sink_arn` output into each source account's account-baseline
#      (observability_sink_arn), in the same region. Set enable_prometheus = true here to add a Managed
#      Prometheus workspace (costs per ingested sample).
inputs = {
  mode            = "sink"
  organization_id = include.root.locals.organization.organization_id

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
