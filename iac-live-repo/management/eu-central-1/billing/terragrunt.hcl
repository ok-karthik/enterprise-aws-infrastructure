# The billing foundation (PLAN 9.2): CUR 2.0 export, cost anomaly monitors per OU and cost allocation tags; applied in the management (payer) account by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/governance/billing"
}

# Prerequisites and order:
#   1. TODO(owner): a real email for the management account in _config/accounts.hcl (the module refuses @example.com).
#   2. Apply once as it is. Then, after resources tagged CostCenter have shown up in billing (up to 24 h), set
#        cost_allocation_tags = ["CostCenter"]
#      below and apply again (a tag key cannot be activated before AWS has seen it).
#   3. Nothing else is needed for Athena: point a table at s3://<cur_bucket_name>/cur2/ (see the module README).

# The Data Exports API only exists in us-east-1, so the module takes a second provider configuration.
generate "provider_us_east_1" {
  path      = "provider_us_east_1.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF2
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
EOF2
}

locals {
  registry = include.root.locals.registry

  # OU name => real account ids. Placeholder ids (000000000xxx) are left out: Cost Explorer would reject them.
  ou_accounts = {
    for ou in distinct([for _, a in local.registry : a.ou if a.ou != "Root"]) :
    ou => [for _, a in local.registry : a.id if a.ou == ou && !startswith(a.id, "00000000")]
  }
}

inputs = {
  anomaly_ou_accounts  = local.ou_accounts
  anomaly_alert_emails = [local.registry["management"].email]

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
