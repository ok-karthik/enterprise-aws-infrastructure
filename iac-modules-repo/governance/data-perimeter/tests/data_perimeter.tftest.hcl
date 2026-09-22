# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_resource "aws_organizations_policy" {
    defaults = {
      id = "p-ab12cd34"
    }
  }
}

variables {
  organization_id = "o-abcde12345"
  target_ou_ids = {
    "Policy-Staging" = "ou-root-aaaaaaaa"
    "Prod"           = "ou-root-bbbbbbbb"
  }
}

run "defaults_cover_the_four_low_risk_services_only" {
  command = plan

  assert {
    condition     = toset(keys(aws_organizations_policy.data_perimeter)) == toset(["s3", "kms", "sqs", "secretsmanager"])
    error_message = "sts must NOT be enabled by default: it needs the federation exemption to be reviewed first."
  }

  assert {
    condition     = alltrue([for s, p in aws_organizations_policy.data_perimeter : p.type == "RESOURCE_CONTROL_POLICY"])
    error_message = "Every policy must be a Resource Control Policy, not a Service Control Policy."
  }
}

run "org_identity_statement_uses_the_real_org_id_and_exempts_aws_services" {
  command = plan

  assert {
    condition     = jsondecode(aws_organizations_policy.data_perimeter["s3"].content).Statement[0].Condition.StringNotEqualsIfExists["aws:PrincipalOrgID"] == "o-abcde12345"
    error_message = "The org-identity statement must check against the real organization id."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.data_perimeter["s3"].content).Statement[0].Condition.BoolIfExists["aws:PrincipalIsAWSService"] == "false"
    error_message = "AWS service principals must be exempt from the organization-membership check."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.data_perimeter["s3"].content).Statement[0].Action == "s3:*"
    error_message = "s3 must be denied broadly (s3:*) for non-org principals."
  }
}

run "every_statement_requires_tls" {
  command = plan

  assert {
    condition = alltrue([
      for s, p in aws_organizations_policy.data_perimeter :
      jsondecode(p.content).Statement[1].Sid == "EnforceTLS" && jsondecode(p.content).Statement[1].Condition.BoolIfExists["aws:SecureTransport"] == "false"
    ])
    error_message = "Every service's second statement must deny non-TLS requests."
  }
}

run "sts_can_be_enabled_and_exempts_only_the_federation_actions" {
  command = plan

  variables {
    enabled_services = ["s3", "sts"]
  }

  assert {
    condition     = !contains(jsondecode(aws_organizations_policy.data_perimeter["sts"].content).Statement[0].Action, "sts:AssumeRoleWithWebIdentity") && !contains(jsondecode(aws_organizations_policy.data_perimeter["sts"].content).Statement[0].Action, "sts:AssumeRoleWithSAML")
    error_message = "GitHub OIDC and SAML federation must stay out of the deny list: they have no aws:PrincipalOrgID yet."
  }

  assert {
    condition     = contains(jsondecode(aws_organizations_policy.data_perimeter["sts"].content).Statement[0].Action, "sts:AssumeRole")
    error_message = "Ordinary role assumption (not federation) must still be denied for non-org principals."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.data_perimeter["sts"].content).Statement[1].Action == jsondecode(aws_organizations_policy.data_perimeter["sts"].content).Statement[0].Action
    error_message = "The TLS statement must cover the same action list as the org-identity statement."
  }
}

run "custom_sts_exemption_narrows_further" {
  command = plan

  variables {
    enabled_services              = ["sts"]
    sts_federation_exempt_actions = ["sts:AssumeRoleWithWebIdentity"]
  }

  assert {
    condition     = contains(jsondecode(aws_organizations_policy.data_perimeter["sts"].content).Statement[0].Action, "sts:AssumeRoleWithSAML")
    error_message = "Removing SAML from the exemption list must deny it (a narrower exemption list must deny more, not less)."
  }
}

run "attaches_only_to_policy_staging_by_default" {
  command = plan

  assert {
    condition     = toset([for k, v in aws_organizations_policy_attachment.data_perimeter : split("/", k)[1]]) == toset(["Policy-Staging"])
    error_message = "By default every RCP attaches to Policy-Staging only."
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.data_perimeter) == 4
    error_message = "4 default services x 1 OU = 4 attachments."
  }
}

run "can_be_widened_to_more_ous" {
  command = plan

  variables {
    target_ous = ["Policy-Staging", "Prod"]
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.data_perimeter) == 8
    error_message = "4 default services x 2 OUs = 8 attachments."
  }
}

run "unknown_service_is_rejected" {
  command = plan

  variables {
    enabled_services = ["sns"]
  }

  expect_failures = [var.enabled_services]
}

run "target_ou_not_in_target_ou_ids_is_rejected" {
  command = plan

  variables {
    target_ous = ["NotARealOu"]
  }

  expect_failures = [var.target_ous]
}

run "placeholder_organization_id_is_rejected" {
  command = plan

  variables {
    organization_id = "o-0000000000"
  }

  expect_failures = [var.organization_id]
}
