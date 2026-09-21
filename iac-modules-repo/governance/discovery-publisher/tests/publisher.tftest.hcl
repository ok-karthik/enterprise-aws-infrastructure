# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

variables {
  env    = "dev"
  region = "eu-central-1"
  parameters = {
    "vpc/id"                = "vpc-12345678"
    "vpc/database_subnets"  = "subnet-1,subnet-2"
    "eks/cluster_name"      = "main-eks-dev"
    "eks/oidc_provider_arn" = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/ABC"
  }
}

run "parameters_use_the_contract_names" {
  command = plan

  assert {
    condition     = aws_ssm_parameter.this["vpc/id"].name == "/platform/dev/eu-central-1/vpc/id" && aws_ssm_parameter.this["eks/cluster_name"].name == "/platform/dev/eu-central-1/eks/cluster_name"
    error_message = "Names must be /platform/<env>/<region>/<key>."
  }

  assert {
    condition     = alltrue([for _, p in aws_ssm_parameter.this : p.type == "String"])
    error_message = "Discovery parameters are plain String metadata."
  }
}

run "unknown_key_is_rejected" {
  command = plan

  variables {
    parameters = { "vpc/secret" = "x" }
  }

  expect_failures = [var.parameters]
}

run "empty_value_is_rejected" {
  command = plan

  variables {
    parameters = { "vpc/id" = "  " }
  }

  expect_failures = [var.parameters]
}

run "unknown_env_is_rejected" {
  command = plan

  variables {
    env = "qa"
  }

  expect_failures = [var.env]
}
