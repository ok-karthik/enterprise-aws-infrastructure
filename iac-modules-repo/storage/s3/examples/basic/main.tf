# Smallest useful use of this module. Also the plan that `make verify-module` checks with conftest.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"

  # Offline plan for `make verify-module` (PLAN 11.1): never talk to AWS. The fake access keys come from the
  # environment that script sets, not from this file. This file is an example, not a module: the
  # "no provider blocks" rule is for the module folder above.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true

  # The same tags root.hcl injects, so the tag policy (require_tags.rego) sees what a real plan would.
  default_tags {
    tags = {
      Environment        = "Dev"
      Service            = "example"
      Project            = "enterprise-aws-platform"
      Owner              = "platform-team"
      DataClassification = "internal"
    }
  }
}

module "s3" {
  source = "../.."

  team_name = "payments"
  app_name  = "ledger"
}
