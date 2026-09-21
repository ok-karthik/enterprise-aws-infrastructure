# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:eu-central-1:111122223333:key/11111111-2222-3333-4444-555555555555"
      key_id = "11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::111122223333:policy/platform-workload-boundary"
    }
  }
}

variables {
  env    = "dev"
  region = "eu-central-1"
  ou     = "NonProd"
}

run "account_wide_defaults_are_secure" {
  command = plan

  assert {
    condition     = aws_s3_account_public_access_block.this.block_public_acls && aws_s3_account_public_access_block.this.block_public_policy && aws_s3_account_public_access_block.this.ignore_public_acls && aws_s3_account_public_access_block.this.restrict_public_buckets
    error_message = "S3 account-level Block Public Access must be fully on."
  }

  assert {
    condition     = aws_ebs_encryption_by_default.this.enabled
    error_message = "EBS encryption by default must be on."
  }

  assert {
    condition     = aws_ec2_instance_metadata_defaults.this.http_tokens == "required"
    error_message = "IMDSv2 must be the account default."
  }

  assert {
    condition     = aws_iam_account_password_policy.this.minimum_password_length >= 14 && aws_iam_account_password_policy.this.require_symbols && aws_iam_account_password_policy.this.password_reuse_prevention == 24
    error_message = "The password policy must be strict."
  }
}

run "kms_keys_rotate" {
  command = plan

  assert {
    condition     = aws_kms_key.general.enable_key_rotation && aws_kms_key.confidential.enable_key_rotation
    error_message = "Both CMKs must have rotation on."
  }

  assert {
    condition     = aws_kms_alias.general.name == "alias/platform-general" && aws_kms_alias.confidential.name == "alias/platform-confidential"
    error_message = "Keys must be reachable by the documented aliases."
  }
}

run "boundary_cannot_be_shed_or_weakened" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_policy.workload_boundary.policy).Statement[1].Sid == "DenyRoleWithoutThisBoundary" && jsondecode(aws_iam_policy.workload_boundary.policy).Statement[1].Condition.StringNotEquals["iam:PermissionsBoundary"] == "arn:aws:iam::111122223333:policy/platform-workload-boundary"
    error_message = "A role under the boundary must only be able to create roles that carry the same boundary."
  }

  assert {
    condition = alltrue([
      for sid in ["DenyBoundaryRemoval", "DenyEditingThisBoundary", "DenyHumanIdentitiesAndKeys", "DenyEditingPlatformRoles", "DenySecurityServiceTampering", "DenyLoweringAccountDefaults", "DenyOrganizationAndIdentity"] :
      contains([for s in jsondecode(aws_iam_policy.workload_boundary.policy).Statement : s.Sid], sid)
    ])
    error_message = "The boundary is missing one of its deny statements."
  }

  assert {
    condition     = jsondecode(aws_iam_policy.workload_boundary.policy).Statement[0].Effect == "Allow" && alltrue([for s in slice(jsondecode(aws_iam_policy.workload_boundary.policy).Statement, 1, length(jsondecode(aws_iam_policy.workload_boundary.policy).Statement)) : s.Effect == "Deny"])
    error_message = "A boundary is one broad Allow followed only by Deny statements."
  }
}

run "discovery_parameters_use_the_contract_names" {
  command = plan

  assert {
    condition     = toset(keys(aws_ssm_parameter.discovery)) == toset(["account/id", "account/ou", "kms/general_key_arn", "kms/confidential_key_arn", "iam/workload_boundary_arn"])
    error_message = "The account dimension of the discovery contract must be published."
  }

  assert {
    condition     = aws_ssm_parameter.discovery["account/ou"].name == "/platform/dev/eu-central-1/account/ou" && aws_ssm_parameter.discovery["account/ou"].value == "NonProd"
    error_message = "Parameter names follow /platform/<env>/<region>/<key>."
  }
}

run "parameters_can_be_switched_off" {
  command = plan

  variables {
    publish_ssm_parameters = false
  }

  assert {
    condition     = length(aws_ssm_parameter.discovery) == 0
    error_message = "publish_ssm_parameters = false must publish nothing."
  }
}

run "alias_is_optional_and_validated" {
  command = plan

  assert {
    condition     = length(aws_iam_account_alias.this) == 0
    error_message = "No alias by default."
  }
}

run "bad_alias_is_rejected" {
  command = plan

  variables {
    account_alias = "Not_Valid"
  }

  expect_failures = [var.account_alias]
}

run "weak_password_policy_is_rejected" {
  command = plan

  variables {
    password_policy_min_length = 8
  }

  expect_failures = [var.password_policy_min_length]
}

run "unknown_env_is_rejected" {
  command = plan

  variables {
    env = "qa"
  }

  expect_failures = [var.env]
}
