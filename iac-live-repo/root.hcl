# root.hcl: included by every stack (terragrunt.hcl) in iac-live-repo.
#
# The folder path IS the configuration:
#   <account>/<region or _global>/<stack>/terragrunt.hcl
#   - <account> must be a key in iac-live-repo/_config/accounts.hcl (the registry)
#   - <region> is an AWS region; _global means "account-wide", run from the primary region
#
# This is the ONLY file that looks anything up. A stack reads these values as include.root.locals.<name>.
locals {
  path_parts   = split("/", path_relative_to_include())
  account_name = local.path_parts[0]
  region_dir   = local.path_parts[1]

  registry     = read_terragrunt_config("${get_repo_root()}/iac-live-repo/_config/accounts.hcl").locals.accounts
  regions      = read_terragrunt_config("${get_repo_root()}/iac-live-repo/_config/regions.hcl").locals
  organization = read_terragrunt_config("${get_repo_root()}/iac-live-repo/_config/organization.hcl").locals

  # An unknown folder name fails here with "Invalid index": add the account to the registry first.
  account             = local.registry[local.account_name]
  account_id          = local.account.id
  env                 = local.account.env # dev | staging | prod | global
  ou                  = local.account.ou
  alias               = local.account.alias
  owner               = local.account.owner
  data_classification = local.account.data_classification
  aws_region          = local.region_dir == "_global" ? local.regions.primary_region : local.region_dir
}

# Wait up to 5 minutes for a state lock instead of failing at once (PLAN 8.3).
terraform {
  extra_arguments "lock_timeout" {
    commands  = ["plan", "apply", "destroy", "import", "refresh"]
    arguments = ["-lock-timeout=5m"]
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  # Fail closed: refuse to run against any account other than the one in the registry for this folder.
  allowed_account_ids = ["${local.account_id}"]

  default_tags {
    tags = {
      Environment        = "${title(local.env)}"
      ManagedBy          = "Terragrunt"
      Account            = "${local.account_name}"
      Project            = "enterprise-aws-platform"
      Service            = "${path_relative_to_include()}"
      Owner              = "${local.owner}"
      DataClassification = "${local.data_classification}"
    }
  }
}
EOF
}

# One state bucket per account and region (created by the Day-0 bootstrap, never by Terragrunt), one key per stack folder.
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "tg-state-${local.account_id}-${local.aws_region}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = "${local.aws_region}"
    encrypt      = true
    use_lockfile = true
  }
}
