# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

run "both_analyzers_cover_the_whole_organization" {
  command = plan

  assert {
    condition     = aws_accessanalyzer_analyzer.external.type == "ORGANIZATION" && aws_accessanalyzer_analyzer.unused.type == "ORGANIZATION_UNUSED_ACCESS"
    error_message = "One organization analyzer for external access and one for unused access."
  }

  assert {
    condition     = one(one(aws_accessanalyzer_analyzer.unused.configuration).unused_access).unused_access_age == 90
    error_message = "Unused access is reported after 90 days by default."
  }
}

run "unused_age_can_be_tuned" {
  command = plan

  variables {
    unused_access_age_days = 30
  }

  assert {
    condition     = one(one(aws_accessanalyzer_analyzer.unused.configuration).unused_access).unused_access_age == 30
    error_message = "The unused-access age follows the variable."
  }
}

run "out_of_range_age_is_rejected" {
  command = plan

  variables {
    unused_access_age_days = 0
  }

  expect_failures = [var.unused_access_age_days]
}
