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
    condition     = toset(keys(aws_ssm_parameter.discovery)) == toset(["account/id", "account/ou", "kms/general_key_arn", "kms/confidential_key_arn", "iam/workload_boundary_arn", "iam/developer_policy_arn"])
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

run "developer_policy_scopes_ec2_by_team_tag" {
  command = plan

  assert {
    condition     = aws_iam_policy.developer.name == "platform-developer"
    error_message = "Identity Center attaches the policy by this name."
  }

  assert {
    condition     = contains(keys({ for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["ControlOwnTeamInstances"].Condition.StringEquals), "aws:ResourceTag/team")
    error_message = "Starting, stopping and terminating EC2 instances must depend on the team tag (ABAC)."
  }

  assert {
    condition     = contains(keys({ for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["LaunchInstancesTaggedForOwnTeam"].Condition.StringEquals), "aws:RequestTag/team")
    error_message = "Instances must be launched with the caller's own team tag."
  }

  assert {
    condition     = !strcontains(aws_iam_policy.developer.policy, "\"Action\":\"*\"") && !strcontains(aws_iam_policy.developer.policy, "\"iam:*\"")
    error_message = "The developer policy must never allow every action or iam:*."
  }
}

# The Developer policy's explicit Denies. Statements are looked up by Sid so the tests do not depend on order.
run "developer_cannot_write_resource_policies" {
  command = plan

  assert {
    condition     = { for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenyResourcePolicyWrites"].Effect == "Deny"
    error_message = "Resource-policy writes must be an explicit Deny."
  }

  assert {
    condition = toset({ for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenyResourcePolicyWrites"].Action) == toset([
      "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketAcl", "s3:PutObjectAcl", "s3:PutBucketPublicAccessBlock",
      "sqs:AddPermission", "sns:AddPermission", "lambda:AddPermission", "ecr:SetRepositoryPolicy",
    ])
    error_message = "The Deny must cover exactly the resource-policy and permission-granting actions."
  }

  assert {
    condition     = { for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenyResourcePolicyWrites"].Resource == "*"
    error_message = "Resource-policy writes are denied on every resource."
  }
}

run "developer_cannot_create_public_lambda_function_urls" {
  command = plan

  assert {
    condition     = toset({ for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenyPublicLambdaFunctionUrls"].Action) == toset(["lambda:CreateFunctionUrlConfig", "lambda:UpdateFunctionUrlConfig"])
    error_message = "Both Create and Update must be covered, or an IAM-auth URL could be switched to public."
  }

  assert {
    condition     = { for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenyPublicLambdaFunctionUrls"].Condition.StringEquals["lambda:FunctionUrlAuthType"] == "NONE"
    error_message = "Only AuthType NONE (public) is denied; AWS_IAM URLs stay allowed."
  }

  assert {
    condition = alltrue([
      for st in jsondecode(aws_iam_policy.developer.policy).Statement :
      st.Effect != "Deny" || contains(keys(st), "Condition") || !strcontains(jsonencode(st.Action), "FunctionUrlConfig")
    ])
    error_message = "No unconditional Deny of function URLs: that would block the IAM-authenticated ones too."
  }
}

run "developer_cannot_write_platform_parameters_but_can_read_them" {
  command = plan

  assert {
    condition = toset({ for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenyPlatformParameterWrites"].Action) == toset([
      "ssm:PutParameter", "ssm:DeleteParameter", "ssm:DeleteParameters", "ssm:LabelParameterVersion", "ssm:AddTagsToResource",
    ])
    error_message = "Every write to a /platform/* parameter must be denied."
  }

  assert {
    condition     = { for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenyPlatformParameterWrites"].Resource == "arn:aws:ssm:*:111122223333:parameter/platform/*"
    error_message = "The Deny applies to /platform/* in this account only."
  }

  assert {
    condition     = !anytrue([for a in { for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenyPlatformParameterWrites"].Action : startswith(a, "ssm:Get") || startswith(a, "ssm:Describe")])
    error_message = "Developers must still be able to READ the discovery contract."
  }
}

run "developer_ssm_access_follows_the_team_tag" {
  command = plan

  assert {
    condition     = toset({ for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenySsmAccessToOtherTeamsInstances"].Action) == toset(["ssm:SendCommand", "ssm:StartSession"])
    error_message = "SendCommand and StartSession are the SSM ways into an instance."
  }

  assert {
    condition     = { for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenySsmAccessToOtherTeamsInstances"].Condition.StringNotEquals["aws:ResourceTag/team"] == "$${aws:PrincipalTag/team}"
    error_message = "SSM access is denied unless the instance's team tag equals the caller's."
  }

  assert {
    condition     = { for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }["DenySsmAccessWithoutTeamTag"].Condition.Null["aws:PrincipalTag/team"] == "true"
    error_message = "A caller without a team tag must not get SSM access to instances."
  }

  assert {
    condition = alltrue([
      for sid in ["DenySsmAccessToOtherTeamsInstances", "DenySsmAccessWithoutTeamTag"] :
      toset({ for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid => st }[sid].Resource) == toset(["arn:aws:ec2:*:111122223333:instance/*", "arn:aws:ssm:*:111122223333:managed-instance/*"])
    ])
    error_message = "Only instance resources are covered: SSM documents (a different resource type) stay allowed."
  }

  assert {
    condition     = !strcontains(aws_iam_policy.developer.policy, ":document/")
    error_message = "No statement may name document resources: running documents must stay allowed."
  }
}

run "developer_policy_keeps_its_allows_and_only_adds_denies" {
  command = plan

  assert {
    condition = toset([for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid if st.Effect == "Deny"]) == toset([
      "DenyResourcePolicyWrites", "DenyPublicLambdaFunctionUrls", "DenyPlatformParameterWrites", "DenySsmAccessToOtherTeamsInstances", "DenySsmAccessWithoutTeamTag",
    ])
    error_message = "The Developer policy has exactly these five Deny statements."
  }

  assert {
    condition     = contains([for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid], "AllowWorkloadServices") && contains([for st in jsondecode(aws_iam_policy.developer.policy).Statement : st.Sid], "ControlOwnTeamInstances")
    error_message = "The Allow statements must still be there."
  }
}

run "security_remediation_role_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role.security_remediation) == 0 && length(aws_iam_role_policy.security_remediation) == 0
    error_message = "No security-remediation role is created while security_remediation_lambda_role_arn is empty."
  }

  assert {
    condition     = output.security_remediation_role_arn == null
    error_message = "The output must be null when the role is off."
  }
}

run "security_remediation_role_trusts_only_the_given_lambda" {
  command = plan

  variables {
    security_remediation_lambda_role_arn = "arn:aws:iam::222233334444:role/auto-remediate-open-ssh-lambda"
  }

  assert {
    condition     = jsondecode(one(aws_iam_role.security_remediation).assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::222233334444:role/auto-remediate-open-ssh-lambda"
    error_message = "The role must trust only the given Lambda execution role."
  }

  assert {
    condition     = jsondecode(one(aws_iam_role_policy.security_remediation).policy).Statement[2].Condition["ForAllValues:StringEquals"]["aws:TagKeys"] == ["remediated-by"]
    error_message = "The role can only ever set the remediated-by tag key."
  }
}

run "bad_security_remediation_lambda_arn_is_rejected" {
  command = plan

  variables {
    security_remediation_lambda_role_arn = "not-an-arn"
  }

  expect_failures = [var.security_remediation_lambda_role_arn]
}

run "vpc_block_public_access_is_on_by_default" {
  command = plan

  assert {
    condition     = one(aws_vpc_block_public_access_options.this).internet_gateway_block_mode == "block-bidirectional"
    error_message = "Internet gateway traffic must be blocked account-wide by default (PLAN 5.7)."
  }
}

run "vpc_block_public_access_can_be_switched_off" {
  command = plan

  variables {
    enable_vpc_block_public_access = false
  }

  assert {
    condition     = length(aws_vpc_block_public_access_options.this) == 0
    error_message = "enable_vpc_block_public_access = false must create nothing."
  }
}
