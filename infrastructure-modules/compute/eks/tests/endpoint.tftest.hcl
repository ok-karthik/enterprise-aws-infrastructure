# Offline unit tests (no AWS credentials): `terraform test` from this module directory.
# Only the variable validation is exercised, so the expected failures stop the plan early.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
      arn        = "arn:aws:iam::111122223333:user/test"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
}

variables {
  cluster_name     = "test"
  vpc_id           = "vpc-12345678"
  subnet_ids       = ["subnet-12345678", "subnet-87654321"]
  enable_karpenter = false
}

run "public_endpoint_without_cidrs_is_rejected" {
  command = plan

  variables {
    cluster_endpoint_public_access = true
    api_allowed_cidrs              = []
  }

  expect_failures = [var.api_allowed_cidrs]
}

run "private_endpoint_needs_no_cidrs" {
  command = plan

  variables {
    cluster_endpoint_public_access = false
    api_allowed_cidrs              = []
  }
}

run "public_endpoint_with_cidrs_is_accepted" {
  command = plan

  variables {
    cluster_endpoint_public_access = true
    api_allowed_cidrs              = ["203.0.113.7/32"]
  }
}
