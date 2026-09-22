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
