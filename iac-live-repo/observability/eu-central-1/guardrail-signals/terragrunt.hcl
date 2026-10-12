# The "are the guardrails on?" dashboard (PLAN 9.3) in the observability account, applied by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/observability/guardrail-signals"
}

# Reads the management account's metrics through cross-account observability. Prerequisites: the OAM sink
# (../oam) is applied, the management account is linked to it (account-baseline observability_sink_arn) and
# the management account's guardrail-signals stack is applied.
inputs = {
  create_alarms      = false
  create_dashboard   = true
  metrics_account_id = include.root.locals.registry["management"].id

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
