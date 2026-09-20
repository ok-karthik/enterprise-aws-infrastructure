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
