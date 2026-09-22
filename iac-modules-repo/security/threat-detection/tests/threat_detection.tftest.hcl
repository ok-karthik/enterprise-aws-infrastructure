# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "222233334444"
    }
  }

  mock_resource "aws_guardduty_detector" {
    defaults = {
      id = "detector-id"
    }
  }
}

run "guardduty_is_organization_wide_with_the_expected_features" {
  command = plan

  assert {
    condition     = aws_guardduty_detector.this.enable
    error_message = "GuardDuty must be enabled for this (delegated administrator) account."
  }

  assert {
    condition     = aws_guardduty_organization_configuration.this.auto_enable_organization_members == "ALL"
    error_message = "GuardDuty must auto-enable for every current and future organization member by default."
  }

  assert {
    condition     = length(aws_guardduty_organization_configuration_feature.this) == 6
    error_message = "All six default GuardDuty features must be configured."
  }

  assert {
    condition     = length(one([for k, f in aws_guardduty_organization_configuration_feature.this : f if k == "EKS_RUNTIME_MONITORING"]).additional_configuration) == 1
    error_message = "EKS_RUNTIME_MONITORING must also enable the EKS_ADDON_MANAGEMENT sub-feature."
  }

  assert {
    condition     = length(one([for k, f in aws_guardduty_organization_configuration_feature.this : f if k == "S3_DATA_EVENTS"]).additional_configuration) == 0
    error_message = "A feature with no sub-feature must not get an additional_configuration block."
  }
}

run "security_hub_subscribes_to_fsbp_and_cis_v3_and_aggregates_every_region" {
  command = plan

  assert {
    condition     = !aws_securityhub_account.this.enable_default_standards
    error_message = "AWS's own default standards must be off: this platform's two standards are subscribed explicitly."
  }

  assert {
    condition     = length(aws_securityhub_standards_subscription.this) == 2
    error_message = "Both fsbp and cis-v3 must be subscribed by default."
  }

  assert {
    condition     = aws_securityhub_standards_subscription.this["fsbp"].standards_arn == "arn:aws:securityhub:eu-central-1::standards/aws-foundational-security-best-practices/v/1.0.0"
    error_message = "The FSBP standard ARN must be built for the current region."
  }

  assert {
    condition     = one(aws_securityhub_finding_aggregator.this).linking_mode == "ALL_REGIONS"
    error_message = "The primary region must create a finding aggregator across every region."
  }

  assert {
    condition     = aws_securityhub_organization_configuration.this.auto_enable && one(aws_securityhub_organization_configuration.this.organization_configuration).configuration_type == "LOCAL"
    error_message = "Security Hub must auto-enable for every organization member, with local (per-member) configuration."
  }
}

run "no_finding_aggregator_outside_the_primary_region" {
  command = plan

  variables {
    is_primary_region = false
  }

  assert {
    condition     = length(aws_securityhub_finding_aggregator.this) == 0
    error_message = "The finding aggregator is a once-per-organization resource: only the primary region creates it."
  }
}

run "inspector_and_macie_cover_the_defaults" {
  command = plan

  assert {
    condition     = aws_inspector2_enabler.this.resource_types == toset(["EC2", "ECR", "LAMBDA"])
    error_message = "Inspector v2 must scan EC2, ECR and Lambda by default."
  }

  assert {
    condition     = one(aws_inspector2_organization_configuration.this.auto_enable).ec2 && one(aws_inspector2_organization_configuration.this.auto_enable).ecr && one(aws_inspector2_organization_configuration.this.auto_enable).lambda
    error_message = "Inspector v2 must auto-enable every resource type it scans, organization-wide."
  }

  assert {
    condition     = one(aws_macie2_account.this).status == "ENABLED"
    error_message = "Macie must be enabled by default."
  }

  assert {
    condition     = one(aws_macie2_organization_configuration.this).auto_enable
    error_message = "Macie must auto-enable organization-wide by default."
  }
}

run "macie_can_be_disabled" {
  command = plan

  variables {
    enable_macie = false
  }

  assert {
    condition     = length(aws_macie2_account.this) == 0 && length(aws_macie2_organization_configuration.this) == 0
    error_message = "enable_macie = false must create nothing."
  }

  assert {
    condition     = output.macie_account_id == null
    error_message = "The output must be null when Macie is disabled."
  }
}

run "detective_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_detective_graph.this) == 0 && length(aws_detective_organization_configuration.this) == 0
    error_message = "Detective must be opt-in."
  }
}

run "detective_can_be_enabled_in_the_primary_region" {
  command = plan

  variables {
    enable_detective = true
  }

  assert {
    condition     = length(aws_detective_graph.this) == 1
    error_message = "enable_detective = true in the primary region must create the graph."
  }

  assert {
    condition     = one(aws_detective_organization_configuration.this).auto_enable
    error_message = "Detective must auto-enable organization-wide once created."
  }
}

run "detective_is_not_created_outside_the_primary_region_even_if_enabled" {
  command = plan

  variables {
    enable_detective  = true
    is_primary_region = false
  }

  assert {
    condition     = length(aws_detective_graph.this) == 0
    error_message = "Detective is a once-per-organization resource: only the primary region creates it, even with enable_detective = true."
  }
}

run "unknown_guardduty_feature_is_rejected" {
  command = plan

  variables {
    guardduty_features = ["NOT_A_FEATURE"]
  }

  expect_failures = [var.guardduty_features]
}

run "unknown_securityhub_standard_is_rejected" {
  command = plan

  variables {
    securityhub_standards = ["nist-800-53"]
  }

  expect_failures = [var.securityhub_standards]
}
