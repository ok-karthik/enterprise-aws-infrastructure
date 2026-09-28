# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}
# The real random provider is used on purpose: mock providers cannot replace ephemeral resources, and it needs no credentials.

variables {
  team_name  = "payments"
  app_name   = "ledger"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
}

run "standalone_uses_a_managed_password_and_no_global_cluster" {
  command = plan

  assert {
    condition     = aws_rds_cluster.this.manage_master_user_password == true && length(aws_rds_global_cluster.this) == 0 && length(aws_secretsmanager_secret.master) == 0
    error_message = "Standalone: RDS manages the password, and no global cluster or module secret is created."
  }

  assert {
    condition     = aws_rds_cluster.this.storage_encrypted && aws_rds_cluster.this.deletion_protection && aws_rds_cluster.this.iam_database_authentication_enabled
    error_message = "Encryption, deletion protection and IAM auth must be on by default."
  }

  assert {
    condition     = length(aws_rds_cluster_instance.this) == 2
    error_message = "Two instances by default (one writer, one reader in another AZ)."
  }
}

run "global_primary_creates_the_global_cluster_and_keeps_the_password_out_of_state" {
  command = plan

  variables {
    mode = "global_primary"
  }

  assert {
    condition     = length(aws_rds_global_cluster.this) == 1 && aws_rds_global_cluster.this[0].storage_encrypted
    error_message = "global_primary must create an encrypted global cluster."
  }

  assert {
    condition     = length(aws_secretsmanager_secret.master) == 1 && aws_rds_cluster.this.master_password_wo_version == 1
    error_message = "global_primary uses a write-only password plus a module-owned secret (Secrets Manager cannot manage a global member's password)."
  }
}

run "global_secondary_joins_without_credentials" {
  command = plan

  variables {
    mode                      = "global_secondary"
    global_cluster_identifier = "payments-ledger-prod-abc123"
    source_region             = "eu-central-1"
    kms_key_id                = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = length(aws_rds_global_cluster.this) == 0 && aws_rds_cluster.this.master_password_wo_version == null && aws_rds_cluster.this.manage_master_user_password == null && length(aws_secretsmanager_secret.master) == 0
    error_message = "A secondary creates no global cluster, no credentials and no secret."
  }

  assert {
    condition     = aws_rds_cluster.this.source_region == "eu-central-1"
    error_message = "A secondary must know the primary's region."
  }
}

run "secondary_needs_a_regional_kms_key" {
  command = plan

  variables {
    mode                      = "global_secondary"
    global_cluster_identifier = "payments-ledger-prod-abc123"
    source_region             = "eu-central-1"
  }

  expect_failures = [var.kms_key_id]
}

run "secondary_needs_the_global_cluster" {
  command = plan

  variables {
    mode          = "global_secondary"
    source_region = "eu-central-1"
    kms_key_id    = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555"
  }

  expect_failures = [var.global_cluster_identifier]
}

run "burstable_classes_are_refused_for_global" {
  command = plan

  variables {
    mode           = "global_primary"
    instance_class = "db.t3.medium"
  }

  expect_failures = [var.instance_class]
}

run "open_to_the_internet_is_refused" {
  command = plan

  variables {
    allowed_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_cidrs]
}
