# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

variables {
  name        = "platform-prod"
  kms_key_arn = "arn:aws:kms:eu-central-1:111122223333:key/11111111-2222-3333-4444-555555555555"
}

run "defaults_back_up_tagged_resources_without_a_copy" {
  command = plan

  assert {
    condition     = length(aws_backup_plan.this) == 1 && length(aws_backup_selection.tagged) == 1 && length([for r in aws_backup_plan.this[0].rule : r if length(r.copy_action) > 0]) == 0
    error_message = "Default: a plan and a tag selection, and no cross-region copy."
  }
}

run "copy_destination_adds_a_cross_region_copy" {
  command = plan

  variables {
    copy_destination_vault_arn = "arn:aws:backup:eu-west-1:111122223333:backup-vault:platform-prod-vault"
  }

  assert {
    condition     = one(one(aws_backup_plan.this[0].rule).copy_action).destination_vault_arn == "arn:aws:backup:eu-west-1:111122223333:backup-vault:platform-prod-vault"
    error_message = "The rule must copy recovery points to the destination vault."
  }
}

run "destination_region_only_has_a_vault" {
  command = plan

  variables {
    create_plan = false
  }

  assert {
    condition     = length(aws_backup_plan.this) == 0 && length(aws_iam_role.backup) == 0
    error_message = "With create_plan = false only the vault (and its policy) exist."
  }
}

run "bad_destination_arn_is_rejected" {
  command = plan

  variables {
    copy_destination_vault_arn = "arn:aws:s3:::nope"
  }

  expect_failures = [var.copy_destination_vault_arn]
}

run "short_retention_is_rejected" {
  command = plan

  variables {
    retention_days = 3
  }

  expect_failures = [var.retention_days]
}
