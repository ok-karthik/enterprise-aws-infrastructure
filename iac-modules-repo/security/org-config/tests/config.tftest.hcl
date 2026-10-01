# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  config_delivery_bucket_name = "tg-log-archive-config-123456789012"
  allowed_regions             = ["eu-central-1", "eu-west-1"]
}

run "primary_region_creates_aggregator_and_packs" {
  command = plan

  variables {
    is_primary_region = true
  }

  assert {
    condition     = aws_config_configuration_recorder.this.name == "platform-config-recorder"
    error_message = "Config recorder must be named platform-config-recorder."
  }

  assert {
    condition     = length(aws_config_configuration_aggregator.organization) == 1
    error_message = "Primary region must deploy organization aggregator."
  }

  assert {
    condition     = length(aws_config_organization_conformance_pack.cis) == 1
    error_message = "CIS conformance pack must be enabled."
  }

  assert {
    condition     = length(aws_config_organization_conformance_pack.nist) == 1
    error_message = "NIST conformance pack must be enabled."
  }

  assert {
    condition     = length(aws_config_organization_conformance_pack.soc2) == 1
    error_message = "SOC2 conformance pack must be enabled."
  }
}

run "secondary_region_skips_aggregator_and_packs" {
  command = plan

  variables {
    is_primary_region = false
  }

  assert {
    condition     = length(aws_config_configuration_aggregator.organization) == 0
    error_message = "Secondary region must not deploy aggregator."
  }

  assert {
    condition     = length(aws_config_organization_conformance_pack.cis) == 0
    error_message = "Secondary region must not deploy organization conformance packs."
  }
}
