# Firewall Manager (PLAN 6.1): FMS WAFv2 + SG audit policies, applied in security-tooling (the delegated FMS administrator) by the owner, once per region. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/security/firewall-manager"
}

# Prerequisites:
#   1. The security-tooling account exists with a real id in the account registry.
#   2. governance/organization registers it as delegated FMS admin:
#        delegated_administrators = { "fms.amazonaws.com" = "<security-tooling account id>" }
#   3. "fms.amazonaws.com" is in aws_service_access_principals.
#   4. Then apply this stack.
inputs = {
  admin_account_id = include.root.locals.account_id

  # TODO(owner): replace with real Workloads OU id(s)
  waf_target_ou_ids = ["ou-xxxx-workloads"]

  # Start in audit mode: observe FMS findings before auto-remediating
  remediation_enabled = false

  # Bot Control for prod: uncomment in the prod stack
  # enable_bot_control = true
  # bot_control_action = "COUNT"

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
