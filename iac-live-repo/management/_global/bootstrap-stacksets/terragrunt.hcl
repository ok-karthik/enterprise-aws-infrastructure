# Service-managed CloudFormation StackSets that roll the Day-0 bootstrap template out to member accounts; applied by the owner from the management account. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/governance/bootstrap-stacksets"
}

# One StackSet per GitHub Environment: the environment sets the apply role's trust subject, and
# auto-deployment can only use the StackSet's own parameters (PLAN 2.0b).
dependency "organization" {
  config_path = "../organization"
  mock_outputs = {
    organizational_unit_ids = {
      "NonProd"        = "ou-mock-12345678"
      "Prod"           = "ou-mock-12345678"
      "Security"       = "ou-mock-12345678"
      "Infrastructure" = "ou-mock-12345678"
    }
  }
}

inputs = {
  # The module stays pure: the template is read here, not inside the module.
  template_body = file("${get_repo_root()}/iac-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml")
  region        = include.root.locals.aws_region

  # CloudFormation copies these onto every resource the stacks create in member accounts.
  # Project, Owner and DataClassification come from the provider default_tags in root.hcl.
  tags = {
    ManagedBy = "CloudFormation"
  }

  stack_sets = {
    bootstrap-nonprod = {
      github_environment      = "dev"
      organizational_unit_ids = [dependency.organization.outputs.organizational_unit_ids["NonProd"]]
    }
    bootstrap-prod = {
      github_environment      = "prod"
      organizational_unit_ids = [dependency.organization.outputs.organizational_unit_ids["Prod"]]
    }
    bootstrap-core = {
      github_environment = "core"
      organizational_unit_ids = [
        dependency.organization.outputs.organizational_unit_ids["Security"],
        dependency.organization.outputs.organizational_unit_ids["Infrastructure"],
      ]
    }
  }
}
