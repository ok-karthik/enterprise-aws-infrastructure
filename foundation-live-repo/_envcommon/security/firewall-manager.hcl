# Common configuration for firewall-manager (PLAN 6.1): FMS WAFv2 + SG audit policies, applied in
# security-tooling (the delegated FMS administrator). Applied by the owner, once per region.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.firewall_manager
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/security/firewall-manager" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/firewall-manager?ref=${local.module_version}"

  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

inputs = {
  admin_account_id = local.account_vars.locals.aws_account_id

  # TODO(owner): replace with real Workloads OU id(s)
  waf_target_ou_ids = ["ou-xxxx-workloads"]

  # Start in audit mode: observe FMS findings before auto-remediating
  remediation_enabled = false

  # Bot Control for prod — uncomment in the prod leaf override
  # enable_bot_control = true
  # bot_control_action = "COUNT"

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
