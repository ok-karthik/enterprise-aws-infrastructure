# Creates and places the member accounts from the registry (entries with create = true); applied by the owner from the management account. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/governance/account-factory"
}

# OU IDs come from the organization stack, which must be applied first.
dependency "organization" {
  config_path = "../organization"

  mock_outputs = {
    organizational_unit_ids = {
      "Security"       = "ou-0000-00000000"
      "Infrastructure" = "ou-0000-00000000"
      "Workloads"      = "ou-0000-00000000"
      "Prod"           = "ou-0000-00000000"
      "NonProd"        = "ou-0000-00000000"
      "Sandbox"        = "ou-0000-00000000"
      "Policy-Staging" = "ou-0000-00000000"
      "Suspended"      = "ou-0000-00000000"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  ou_ids = dependency.organization.outputs.organizational_unit_ids

  # Only entries with create = true. Placeholders and the management account are never vended.
  accounts = {
    for name, a in include.root.locals.registry : name => { email = a.email, ou = a.ou } if a.create
  }

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
