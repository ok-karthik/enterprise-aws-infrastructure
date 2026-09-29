# Smallest useful use of this module. Also the plan that `make verify-module` checks with conftest.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
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

module "failover" {
  source = "../.."

  zone_id     = "Z0123456789ABCDEFGHIJ"
  record_name = "api.example.com"
  primary     = { dns_name = "primary-alb.eu-central-1.elb.amazonaws.com", zone_id = "Z215JYRZR1TBD5" }
  secondary   = { dns_name = "dr-alb.eu-west-1.elb.amazonaws.com", zone_id = "Z32O12XQLNTSW2" }
  health_check = {
    fqdn = "primary-alb.eu-central-1.elb.amazonaws.com"
  }
}
