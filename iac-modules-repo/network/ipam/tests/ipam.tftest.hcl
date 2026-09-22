# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_resource "aws_vpc_ipam" {
    defaults = {
      private_default_scope_id = "ipam-scope-priv-0123456789abcdef0"
    }
  }

  mock_resource "aws_vpc_ipam_pool" {
    defaults = {
      id  = "ipam-pool-0123456789abcdef0"
      arn = "arn:aws:ec2::222233334444:ipam-pool/ipam-pool-0123456789abcdef0"
    }
  }

  mock_resource "aws_ram_resource_share" {
    defaults = {
      arn = "arn:aws:ram:eu-central-1:222233334444:resource-share/ipam-env-pools"
    }
  }
}

variables {
  organization_id  = "o-abcde12345"
  workloads_ou_arn = "arn:aws:organizations::111122223333:ou/o-abcde12345/ou-root-cccccccc"
}

run "one_regional_pool_per_entry_carved_from_the_top_level_pool" {
  command = apply

  assert {
    condition     = toset(keys(aws_vpc_ipam_pool.regional)) == toset(["eu-central-1", "eu-west-1"])
    error_message = "One regional pool per entry in regional_pools."
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional["eu-central-1"].source_ipam_pool_id == aws_vpc_ipam_pool.top_level.id
    error_message = "Every regional pool must be carved from the top-level pool."
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.top_level.cidr == "10.0.0.0/8"
    error_message = "The top-level pool must get the configured CIDR."
  }
}

run "each_region_gets_a_prod_and_a_nonprod_env_pool" {
  command = apply

  assert {
    condition     = toset(keys(aws_vpc_ipam_pool.env)) == toset(["eu-central-1/prod", "eu-central-1/nonprod", "eu-west-1/prod", "eu-west-1/nonprod"])
    error_message = "Every region must get exactly a prod and a nonprod env pool."
  }

  assert {
    condition     = aws_vpc_ipam_pool.env["eu-central-1/prod"].source_ipam_pool_id == aws_vpc_ipam_pool.regional["eu-central-1"].id
    error_message = "An env pool must be carved from its own region's pool, not another region's."
  }

  assert {
    condition     = aws_vpc_ipam_pool.env["eu-central-1/prod"].allocation_default_netmask_length == 10
    error_message = "The env pool's default allocation netmask must come from prod_env_netmask_length."
  }
}

run "only_env_pools_are_shared_with_the_workloads_ou" {
  command = apply

  assert {
    condition     = length(aws_ram_resource_association.pools) == 4
    error_message = "Every env pool (4 total: 2 regions x 2 envs), and only env pools, must be shared."
  }

  assert {
    condition     = aws_ram_principal_association.workloads_ou.principal == "arn:aws:organizations::111122223333:ou/o-abcde12345/ou-root-cccccccc"
    error_message = "The share must be with the given Workloads OU."
  }
}

run "placeholder_organization_id_is_rejected" {
  command = plan

  variables {
    organization_id = "o-0000000000"
  }

  expect_failures = [var.organization_id]
}

run "bad_workloads_ou_arn_is_rejected" {
  command = plan

  variables {
    workloads_ou_arn = "arn:aws:iam::111122223333:role/not-an-ou"
  }

  expect_failures = [var.workloads_ou_arn]
}

run "regional_pools_key_must_match_its_own_locale" {
  command = plan

  variables {
    regional_pools = {
      eu-central-1 = { locale = "eu-west-1", cidr = "10.0.0.0/9" }
    }
  }

  expect_failures = [var.regional_pools]
}
