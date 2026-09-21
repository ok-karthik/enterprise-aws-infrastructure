# This file generates the backend.tf and provider.tf automatically
# for every child module.

locals {
  # 1. Load the variables from your file structure
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # The environment is a property of the account (one account = one env), not of the folder name.
  env = local.account_vars.locals.env

  # 2. Extract them into simple local variables
  aws_region    = local.region_vars.locals.aws_region
  account_alias = local.account_vars.locals.account_name
  cluster_name  = local.env_vars.locals.cluster_name

  # 3. The account this stack is DECLARED to belong to (account.hcl).
  # Do not use get_aws_account_id() here: it returns whatever account the caller is logged
  # in to, so `allowed_account_ids` would compare the caller with itself and never fail.
  account_id = local.account_vars.locals.aws_account_id
  owner      = local.account_vars.locals.owner
  data_class = local.account_vars.locals.data_classification
}


# Generate an AWS provider block
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  # Fail closed: refuse to run against any account other than the one declared in account.hcl.
  allowed_account_ids = ["${local.account_id}"]

  default_tags {
    tags = {
      Environment        = "${title(local.env)}"
      ManagedBy          = "Terragrunt"
      Account            = "${local.account_alias}"
      Project            = "enterprise-aws-platform"
      Service            = "${path_relative_to_include()}"
      Owner              = "${local.owner}"
      DataClassification = "${local.data_class}"
    }
  }
}
EOF
}

# Configure S3 State Backend automatically
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    # The state bucket is created by the Day-0 CloudFormation stack (foundation-live-repo/_bootstrap/),
    # never by Terragrunt: no command in this repo may pass --backend-bootstrap. The name must
    # match the template: tg-state-<account-id>-<region>.
    bucket       = "tg-state-${local.account_id}-${local.aws_region}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = "${local.aws_region}"
    encrypt      = true
    use_lockfile = true
  }
}
