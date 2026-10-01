# Common configuration for the billing foundation (PLAN 9.2): CUR 2.0 export, cost anomaly monitors per OU and cost
# allocation tags. Applied in the management (payer) account by the owner.

terraform {
  source = local.module_source
}

locals {
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.billing
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/governance/billing" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/governance/billing?ref=${local.module_version}"

  registry = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")

  # OU name => real account ids. Placeholder ids (000000000xxx) are left out: Cost Explorer would reject them.
  ou_accounts = {
    for ou in distinct([for _, a in local.registry.locals.accounts : a.ou if a.ou != "Root"]) :
    ou => [for _, a in local.registry.locals.accounts : a.id if a.ou == ou && !startswith(a.id, "00000000")]
  }
}

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

inputs = {
  anomaly_ou_accounts  = local.ou_accounts
  anomaly_alert_emails = [local.registry.locals.accounts["management"].email]
  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
