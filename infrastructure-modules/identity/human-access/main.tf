terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. Platform Administrator Permission Set
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "platform_admin" {
  name             = "${var.name_prefix}-PlatformAdmin"
  description      = "Full administrative access for Platform and SRE engineers"
  instance_arn     = var.sso_instance_arn
  session_duration = var.session_duration

  tags = merge(
    {
      Service = "identity-human-access"
      Role    = "PlatformAdmin"
    },
    var.tags
  )
}

resource "aws_ssoadmin_managed_policy_attachment" "platform_admin" {
  instance_arn       = var.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.platform_admin.arn
}

# ------------------------------------------------------------------------------
# 2. Application Developer Permission Set
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "developer" {
  name             = "${var.name_prefix}-Developer"
  description      = "Scoped developer access for deploying and debugging microservices"
  instance_arn     = var.sso_instance_arn
  session_duration = var.session_duration

  tags = merge(
    {
      Service = "identity-human-access"
      Role    = "Developer"
    },
    var.tags
  )
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_view" {
  instance_arn       = var.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
}

# ------------------------------------------------------------------------------
# 3. Security & Compliance Auditor Permission Set
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "auditor" {
  name             = "${var.name_prefix}-AuditorReadOnly"
  description      = "Read-only security audit access for compliance and FinOps"
  instance_arn     = var.sso_instance_arn
  session_duration = var.session_duration

  tags = merge(
    {
      Service = "identity-human-access"
      Role    = "Auditor"
    },
    var.tags
  )
}

resource "aws_ssoadmin_managed_policy_attachment" "auditor_security" {
  instance_arn       = var.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
}
