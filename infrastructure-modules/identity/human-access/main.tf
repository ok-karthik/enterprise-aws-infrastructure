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
  count            = var.sso_instance_arn != "" ? 1 : 0
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
  count              = var.sso_instance_arn != "" ? 1 : 0
  instance_arn       = var.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.platform_admin[0].arn
}

# ------------------------------------------------------------------------------
# 2. Application Developer Permission Set
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "developer" {
  count            = var.sso_instance_arn != "" ? 1 : 0
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
  count              = var.sso_instance_arn != "" ? 1 : 0
  instance_arn       = var.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.developer[0].arn
}

# ------------------------------------------------------------------------------
# 3. Security & Compliance Auditor Permission Set
# ------------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "auditor" {
  count            = var.sso_instance_arn != "" ? 1 : 0
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
  count              = var.sso_instance_arn != "" ? 1 : 0
  instance_arn       = var.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
  permission_set_arn = aws_ssoadmin_permission_set.auditor[0].arn
}

# ------------------------------------------------------------------------------
# 4. EKS Access Entries & Cluster View Associations
# ------------------------------------------------------------------------------
resource "aws_eks_access_entry" "team" {
  for_each = var.cluster_name != "" ? var.team_access : {}

  cluster_name      = var.cluster_name
  principal_arn     = each.value.principal_arn
  kubernetes_groups = each.value.k8s_groups
  type              = "STANDARD"

  tags = merge(
    {
      Service = "identity-human-access"
    },
    var.tags
  )
}

resource "aws_eks_access_policy_association" "team_view" {
  for_each = var.cluster_name != "" ? var.team_access : {}

  cluster_name  = var.cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }
}
