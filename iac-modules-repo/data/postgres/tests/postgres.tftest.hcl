# Offline unit tests (no AWS credentials): `terraform test` from this module directory.
# They pin the database settings that the Checkov backlog fixes (PLAN 8.9) depend on.

mock_provider "aws" {}
mock_provider "random" {}

variables {
  team_name = "payments"
  app_name  = "ledger"
}

run "database_hardening_is_on" {
  command = plan

  assert {
    condition     = aws_db_instance.this.iam_database_authentication_enabled == true
    error_message = "IAM database authentication must be enabled."
  }

  assert {
    condition     = aws_db_instance.this.copy_tags_to_snapshot == true
    error_message = "Tags must be copied to snapshots."
  }

  assert {
    condition     = aws_db_instance.this.auto_minor_version_upgrade == true
    error_message = "Automatic minor version upgrades must be enabled."
  }

  assert {
    condition     = contains(aws_db_instance.this.enabled_cloudwatch_logs_exports, "postgresql") && contains(aws_db_instance.this.enabled_cloudwatch_logs_exports, "upgrade")
    error_message = "The postgresql and upgrade logs must be exported to CloudWatch."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted == true
    error_message = "Storage must stay encrypted."
  }
}
