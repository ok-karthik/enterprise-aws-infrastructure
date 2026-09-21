# Common configuration for the member-account bootstrap StackSets (PLAN 2.0b).
# Applied from the management account only (foundation-live-repo/_global/...), by the owner.

terraform {
  source = "${get_repo_root()}/iac-modules-repo/governance/bootstrap-stacksets"
}

locals {
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
