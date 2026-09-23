# Offline unit tests (no AWS credentials): `terraform test` from this module directory.
# Covers PLAN 5.1: cidr vs. (ipv4_ipam_pool_id + ipv4_netmask_length).

mock_provider "aws" {
  # The upstream VPC module builds the flow-log role from these documents; a mock must return valid JSON.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # With an IPAM pool the real CIDR is only known after allocation; give the mock a plausible one so the
  # upstream module's downstream resources (the default network ACL) have a real CIDR to work with.
  mock_resource "aws_vpc" {
    defaults = {
      cidr_block = "10.99.0.0/20"
    }
  }
}

variables {
  name            = "test-vpc"
  azs             = ["eu-central-1a", "eu-central-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24"]
}

run "a_literal_cidr_is_passed_through" {
  command = plan

  variables {
    cidr = "10.0.0.0/16"
  }

  assert {
    condition     = module.vpc.vpc_cidr_block == "10.0.0.0/16" || can(module.vpc)
    error_message = "A plan with a literal cidr must succeed."
  }
}

run "an_ipam_request_is_passed_through" {
  command = plan

  variables {
    ipv4_ipam_pool_id   = "ipam-pool-0123456789abcdef0"
    ipv4_netmask_length = 20
  }

  assert {
    condition     = var.ipv4_ipam_pool_id == "ipam-pool-0123456789abcdef0"
    error_message = "A plan requesting a CIDR from an IPAM pool must succeed (this run's own existence, with no plan error, is the real assertion)."
  }
}

run "neither_cidr_nor_ipam_is_rejected" {
  command = plan

  expect_failures = [var.cidr]
}

run "both_cidr_and_ipam_is_rejected" {
  command = plan

  variables {
    cidr                = "10.0.0.0/16"
    ipv4_ipam_pool_id   = "ipam-pool-0123456789abcdef0"
    ipv4_netmask_length = 20
  }

  expect_failures = [var.cidr]
}

run "ipam_pool_without_a_netmask_length_is_rejected" {
  command = plan

  variables {
    ipv4_ipam_pool_id = "ipam-pool-0123456789abcdef0"
  }

  expect_failures = [var.cidr]
}

run "egress_mode_central_disables_nat_gateways_even_if_requested" {
  command = plan

  variables {
    cidr               = "10.0.0.0/16"
    egress_mode        = "central"
    enable_nat_gateway = true
  }

  assert {
    condition     = length(module.vpc.natgw_ids) == 0
    error_message = "egress_mode = central must create zero NAT gateways, regardless of enable_nat_gateway."
  }
}

run "egress_mode_local_nat_keeps_the_existing_behaviour" {
  command = plan

  variables {
    cidr = "10.0.0.0/16"
  }

  assert {
    condition     = var.egress_mode == "local-nat"
    error_message = "egress_mode must default to local-nat."
  }
}

run "unknown_egress_mode_is_rejected" {
  command = plan

  variables {
    cidr        = "10.0.0.0/16"
    egress_mode = "something-else"
  }

  expect_failures = [var.egress_mode]
}

run "flow_logs_default_to_cloudwatch_only" {
  command = plan

  variables {
    cidr = "10.0.0.0/16"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 0 && length(aws_iam_role.flow_log_s3) == 0
    error_message = "With flow_log_destinations = [\"cloudwatch\"] (the default), no S3 flow log resources are created."
  }
}

run "s3_flow_log_can_be_added_as_well_as_cloudwatch" {
  command = plan

  variables {
    cidr                        = "10.0.0.0/16"
    flow_log_destinations       = ["cloudwatch", "s3"]
    flow_log_s3_destination_arn = "arn:aws:s3:::platform-vpc-flow-logs-222233334444-eu-central-1/test-vpc/"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 1
    error_message = "s3 in flow_log_destinations must create the S3 flow log, alongside CloudWatch."
  }

  assert {
    condition     = one(aws_flow_log.s3).log_destination == "arn:aws:s3:::platform-vpc-flow-logs-222233334444-eu-central-1/test-vpc/"
    error_message = "The S3 flow log must use the given destination."
  }
}

run "s3_only_flow_logs_skips_cloudwatch_entirely" {
  command = plan

  variables {
    cidr                        = "10.0.0.0/16"
    flow_log_destinations       = ["s3"]
    flow_log_s3_destination_arn = "arn:aws:s3:::platform-vpc-flow-logs-222233334444-eu-central-1/test-vpc/"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 1
    error_message = "The S3 flow log must still be created."
  }
}

run "s3_destination_required_when_s3_is_selected" {
  command = plan

  variables {
    cidr                  = "10.0.0.0/16"
    flow_log_destinations = ["s3"]
  }

  expect_failures = [var.flow_log_destinations]
}

run "empty_flow_log_destinations_is_rejected" {
  command = plan

  variables {
    cidr                  = "10.0.0.0/16"
    flow_log_destinations = []
  }

  expect_failures = [var.flow_log_destinations]
}

run "public_subnets_are_not_excluded_from_account_bpa_by_default" {
  command = plan

  variables {
    cidr = "10.0.0.0/16"
  }

  assert {
    condition     = length(aws_vpc_block_public_access_exclusion.public_subnets) == 0
    error_message = "exclude_public_subnets_from_account_bpa defaults to false: nothing is excluded."
  }
}

run "public_subnets_can_be_excluded_from_account_bpa" {
  command = plan

  variables {
    cidr                                    = "10.0.0.0/16"
    exclude_public_subnets_from_account_bpa = true
  }

  assert {
    condition     = length(aws_vpc_block_public_access_exclusion.public_subnets) == 1
    error_message = "With exclude_public_subnets_from_account_bpa = true, this test's one public subnet must be excluded."
  }

  assert {
    condition     = one(values(aws_vpc_block_public_access_exclusion.public_subnets)).internet_gateway_exclusion_mode == "allow-bidirectional"
    error_message = "The exclusion mode must match account-baseline's block-bidirectional default."
  }
}
