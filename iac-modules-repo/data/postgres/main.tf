terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

# RDS identifiers are lowercase-only, so upper must be false here.
resource "random_string" "db_suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  name_prefix = lower("${var.team_name}-${var.app_name}-${var.env}")
  identifier  = "${substr(local.name_prefix, 0, 56)}-${random_string.db_suffix.result}"
}

resource "aws_db_subnet_group" "this" {
  count       = length(var.subnet_ids) > 0 ? 1 : 0
  name        = "${local.identifier}-subnets"
  subnet_ids  = var.subnet_ids
  description = "Database subnet group for ${local.identifier}"

  tags = merge(
    {
      Name      = "${local.identifier}-subnets"
      ManagedBy = "Terragrunt-Wrapper"
      Service   = "data-postgres"
    },
    var.tags
  )
}

resource "aws_security_group" "this" {
  #checkov:skip=CKV_AWS_382: "RDS needs outbound access for S3 import/export, extensions and replication; egress is governed by the VPC (endpoints, NACLs, route tables) and the SG allows ingress only from the private supernet on 5432"
  count       = var.vpc_id != "" ? 1 : 0
  name        = "${local.identifier}-sg"
  description = "PostgreSQL access for ${var.team_name}/${var.app_name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from within the private supernet"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name      = "${local.identifier}-sg"
      ManagedBy = "Terragrunt-Wrapper"
      Service   = "data-postgres"
    },
    var.tags
  )
}

resource "aws_db_instance" "this" {
  # Optional features that cost money or are the tenant's call, not a baseline guardrail. Each is left off on
  # purpose in this minimal, NonProd-first capability; a tenant that needs one overrides it in its own stack.
  #checkov:skip=CKV_AWS_157: "Multi-AZ doubles the instance cost; NonProd/Sandbox default. Production high availability is the Aurora option planned in PLAN 7.3"
  #checkov:skip=CKV_AWS_293: "skip_final_snapshot is true and tenant stacks must be destroyable in NonProd/Sandbox; production sets deletion protection in its own stack until the module takes a variable for it"
  #checkov:skip=CKV_AWS_118: "Enhanced monitoring needs an IAM role and is billed per instance; CloudWatch basic metrics are on. Enable per tenant when needed"
  #checkov:skip=CKV_AWS_353: "Performance Insights is an optional diagnostics feature, not a security control; enable per tenant when needed"
  #checkov:skip=CKV2_AWS_30: "Query logging needs a parameter group with tenant-specific log_statement settings. The postgresql and upgrade logs are exported to CloudWatch (enabled_cloudwatch_logs_exports); tenants tune verbosity"
  identifier     = local.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = 20
  username          = "dbadmin"

  # manage_master_user_password hands the credential to AWS Secrets Manager and
  # rotates it there without writing plaintext into state.
  manage_master_user_password = true

  db_subnet_group_name   = length(var.subnet_ids) > 0 ? aws_db_subnet_group.this[0].name : null
  vpc_security_group_ids = var.vpc_id != "" ? [aws_security_group.this[0].id] : null

  # Guardrails enforced for all tenants
  publicly_accessible     = false
  storage_encrypted       = true
  backup_retention_period = var.backup_retention_days
  skip_final_snapshot     = true

  # Safe hardening that costs nothing: IAM database authentication (an extra way in, not a replacement),
  # snapshots keep the instance's tags, minor engine versions are patched, and the engine and upgrade logs
  # go to CloudWatch.
  iam_database_authentication_enabled = true
  copy_tags_to_snapshot               = true
  auto_minor_version_upgrade          = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]

  tags = merge(
    {
      Name      = local.identifier
      Owner     = var.team_name
      ManagedBy = "Terragrunt-Wrapper"
      Service   = "data-postgres"
    },
    var.tags
  )
}
