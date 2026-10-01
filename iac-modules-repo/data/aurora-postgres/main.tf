locals {
  name_prefix = lower("${var.team_name}-${var.app_name}-${var.env}")
  identifier  = "${substr(local.name_prefix, 0, 56)}-${random_string.suffix.result}"

  is_global    = var.mode != "standalone"
  is_primary   = var.mode != "global_secondary" # standalone and global_primary own a writer and credentials
  needs_secret = var.mode == "global_primary"   # Secrets Manager cannot manage the password of a global cluster member
  kms_key_id   = var.kms_key_id != "" ? var.kms_key_id : null

  # Backup = "true" opts the cluster into the tag-based plan of data/backup (PLAN 7.3).
  tags = merge({ Owner = var.team_name, Service = "data-aurora-postgres", Backup = "true" }, var.tags)
}

# RDS identifiers are lowercase-only.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_db_subnet_group" "this" {
  name        = "${local.identifier}-subnets"
  subnet_ids  = var.subnet_ids
  description = "Aurora subnet group for ${local.identifier}"
  tags        = merge({ Name = "${local.identifier}-subnets" }, local.tags)
}

resource "aws_security_group" "this" {
  #checkov:skip=CKV_AWS_382: "The database only needs replies to inbound connections; egress is governed by the VPC. Same reasoning as data/postgres."
  name_prefix = "${local.identifier}-sg-"
  description = "PostgreSQL access for ${var.team_name}/${var.app_name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from the allowed CIDRs"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "${local.identifier}-sg" }, local.tags)

  # PLAN 8.4: name_prefix gives a replacement a different name, so it can be created before the old one is
  # destroyed. Without it a change that forces replacement fails on "already exists" or drops traffic.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_global_cluster" "this" {
  count = var.mode == "global_primary" ? 1 : 0

  global_cluster_identifier = local.identifier
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

# The master password of a global cluster member cannot be managed by Secrets Manager (AWS limitation), so in
# global_primary mode it is generated here as an EPHEMERAL value: it is passed to RDS and to the secret through
# write-only arguments and is never written to the Terraform state or plan.
ephemeral "random_password" "master" {
  count   = local.needs_secret ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "master" {
  #checkov:skip=CKV2_AWS_57: "Automatic rotation of a global cluster's password needs a rotation Lambda per region; planned with the platform secrets phase. Documented in the README."
  count = local.needs_secret ? 1 : 0

  name                    = "${local.identifier}/master"
  description             = "Master credentials for the Aurora global cluster ${local.identifier}"
  kms_key_id              = local.kms_key_id
  recovery_window_in_days = 7
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "master" {
  count = local.needs_secret ? 1 : 0

  secret_id                = aws_secretsmanager_secret.master[0].id
  secret_string_wo         = jsonencode({ username = "dbadmin", password = ephemeral.random_password.master[0].result })
  secret_string_wo_version = 1
}

resource "aws_rds_cluster" "this" {
  #checkov:skip=CKV2_AWS_8: "The backup plan is a separate stack (data/backup) that selects resources by the Backup=true tag, which this cluster carries; Checkov cannot see across stacks. Aurora automated backups are on as well (backup_retention_period)"
  #checkov:skip=CKV2_AWS_27: "Query logging depends on a tenant parameter group; the postgresql log is exported to CloudWatch"
  #checkov:skip=CKV_AWS_162: "IAM database authentication is on; see iam_database_authentication_enabled"
  cluster_identifier = local.identifier
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version

  # Global members: attach to the global cluster (the primary creates it, a secondary joins it).
  global_cluster_identifier = local.is_global ? (var.mode == "global_primary" ? aws_rds_global_cluster.this[0].id : var.global_cluster_identifier) : null
  source_region             = var.mode == "global_secondary" ? var.source_region : null

  # Credentials only on a writer cluster; a secondary inherits the data (and the users) from the primary.
  master_username             = local.is_primary ? "dbadmin" : null
  manage_master_user_password = var.mode == "standalone" ? true : null
  master_password_wo          = local.needs_secret ? ephemeral.random_password.master[0].result : null
  master_password_wo_version  = local.needs_secret ? 1 : null

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]

  storage_encrypted                   = true
  kms_key_id                          = local.kms_key_id
  backup_retention_period             = var.backup_retention_days
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = !var.deletion_protection
  final_snapshot_identifier           = var.deletion_protection ? "${local.identifier}-final" : null
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  tags = merge({ Name = local.identifier }, local.tags)

  lifecycle {
    # After a managed failover or a global engine upgrade AWS changes these outside Terraform.
    ignore_changes = [engine_version, global_cluster_identifier, replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "this" {
  #checkov:skip=CKV_AWS_118: "Enhanced monitoring needs an IAM role per tenant; CloudWatch metrics and Performance Insights are on"
  count = var.instance_count

  identifier                 = "${local.identifier}-${count.index + 1}"
  cluster_identifier         = aws_rds_cluster.this.id
  engine                     = aws_rds_cluster.this.engine
  engine_version             = aws_rds_cluster.this.engine_version
  instance_class             = var.instance_class
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  performance_insights_enabled    = true
  performance_insights_kms_key_id = local.kms_key_id

  tags = merge({ Name = "${local.identifier}-${count.index + 1}" }, local.tags)
}
