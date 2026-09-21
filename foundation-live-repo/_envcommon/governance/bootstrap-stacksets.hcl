# Common configuration for the member-account bootstrap StackSets (PLAN 2.0b).
# Applied from the management account only (foundation-live-repo/_global/...), by the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.bootstrap_stacksets
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/governance/bootstrap-stacksets" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/governance/bootstrap-stacksets?ref=${local.module_version}"

  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region  = local.region_vars.locals.aws_region
}

inputs = {
  # The module stays pure: the template is read here, not inside the module.
  template_body = file("${get_repo_root()}/foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml")
  region        = local.aws_region

  # CloudFormation copies these onto every resource the stacks create in member accounts.
  # Project, Owner and DataClassification come from the provider default_tags in root.hcl.
  tags = {
    ManagedBy = "CloudFormation"
  }
}
