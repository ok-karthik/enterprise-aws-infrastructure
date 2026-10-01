locals {
  copy = var.copy_destination_vault_arn != ""
}

resource "aws_backup_vault" "this" {
  name        = "${var.name}-vault"
  kms_key_arn = var.kms_key_arn
  tags        = var.tags
}

# A recovery point can only be deleted by the backup service or with an explicit permission: deny it for everyone else.
resource "aws_backup_vault_policy" "this" {
  backup_vault_name = aws_backup_vault.this.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyDeleteRecoveryPoints"
      Effect    = "Deny"
      Principal = "*"
      Action    = ["backup:DeleteRecoveryPoint", "backup:UpdateRecoveryPointLifecycle", "backup:PutBackupVaultAccessPolicy"]
      Resource  = "*"
      Condition = {
        StringNotLike = { "aws:PrincipalArn" = "arn:aws:iam::*:role/${var.name}-break-glass" }
      }
    }]
  })
}

resource "aws_iam_role" "backup" {
  count = var.create_plan ? 1 : 0

  name = "${var.name}-backup"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = var.create_plan ? toset(["AWSBackupServiceRolePolicyForBackup", "AWSBackupServiceRolePolicyForRestores"]) : toset([])

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/${each.value}"
}

resource "aws_backup_plan" "this" {
  count = var.create_plan ? 1 : 0

  name = "${var.name}-daily"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.this.name
    schedule          = var.schedule

    lifecycle {
      delete_after = var.retention_days
    }

    dynamic "copy_action" {
      for_each = local.copy ? [1] : []

      content {
        destination_vault_arn = var.copy_destination_vault_arn

        lifecycle {
          delete_after = var.copy_retention_days
        }
      }
    }
  }

  tags = var.tags
}

resource "aws_backup_selection" "tagged" {
  count = var.create_plan ? 1 : 0

  name         = "${var.name}-tagged"
  plan_id      = aws_backup_plan.this[0].id
  iam_role_arn = aws_iam_role.backup[0].arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.selection_tag_key
    value = var.selection_tag_value
  }
}
