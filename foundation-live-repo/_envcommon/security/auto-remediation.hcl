# Common configuration for the auto-remediation Lambda (PLAN 4.9): removes open SSH/RDP security group
# rules. Applied in security-tooling. Applied by the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.auto_remediation
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/security/auto-remediation" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/auto-remediation?ref=${local.module_version}"

  organization = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/organization.hcl")
}

dependency "security_alerts" {
  config_path = "${get_terragrunt_dir()}/../security-alerts"

  mock_outputs = {
    topic_arn = "arn:aws:sns:eu-central-1:222233334444:security-alerts-alerts"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  organization_id = local.organization.locals.organization_id
  alert_topic_arn = dependency.security_alerts.outputs.topic_arn

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
