# Organization-wide IAM Access Analyzer, created in the account that is DELEGATED ADMINISTRATOR for
# access-analyzer.amazonaws.com (security-tooling): the delegation is registered by the organization
# module in the management account (delegated_administrators). Two analyzers:
#   - external access: resources (S3 buckets, roles, KMS keys, ...) that can be reached from outside the
#     organization, in every account;
#   - unused access: roles and users with permissions or credentials nobody has used for
#     var.unused_access_age_days days, in every account.
# Analyzers are regional: apply this in every region you use. Findings reach Security Hub on their own once
# Security Hub is enabled with this account as its delegated administrator (PLAN 4.4); nothing has to be
# configured here for that.

locals {
  tags = merge({ Service = "security-access-analyzer", ManagedBy = "Terragrunt-Wrapper" }, var.tags)
}

resource "aws_accessanalyzer_analyzer" "external" {
  analyzer_name = var.external_analyzer_name
  type          = "ORGANIZATION"

  tags = local.tags
}

resource "aws_accessanalyzer_analyzer" "unused" {
  analyzer_name = var.unused_analyzer_name
  type          = "ORGANIZATION_UNUSED_ACCESS"

  configuration {
    unused_access {
      unused_access_age = var.unused_access_age_days
    }
  }

  tags = local.tags
}
