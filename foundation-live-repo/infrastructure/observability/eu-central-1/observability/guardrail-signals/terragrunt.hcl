include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/observability/guardrail-signals.hcl"
  expose = true
}

# The dashboard "are the guardrails on?", reading the management account's metrics through cross-account
# observability. Prerequisites: the OAM sink (../oam) is applied, the management account is linked to it
# (account-baseline observability_sink_arn) and the management account's guardrail-signals stack is applied.
inputs = {
  create_alarms      = false
  create_dashboard   = true
  metrics_account_id = include.envcommon.locals.registry.locals.accounts["management"].id

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
