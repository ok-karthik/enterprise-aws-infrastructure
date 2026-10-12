# Account registry: the single source of truth for which AWS accounts exist. The account factory
# vends the entries with create = true; scripts/check-account-registry.sh fails CI if an
# account folder of iac-live-repo (<ou folder>/<account>/<region|_global>/<stack>) has no entry here or is not under the
# folder of its registry OU (mapped through organization.hcl). The folder name IS the account key (see root.hcl).
#
# The ids and emails below are placeholders. Real IDs and emails come from accounts.local.hcl (gitignored) if
# present, or supplied via the ACCOUNTS_LOCAL_HCL repository variable in CI (see accounts.local.hcl.example). An entry
# there overrides the same-named entry here, field by field.
#
# Fields:
#   - id     : the 12-digit account ID (000000000xxx = placeholder: CI skips the account, bootstrap refuses it)
#   - ou     : OU name from the organization module ("Root" = directly under the root, only the management account)
#   - env    : global | dev | staging | prod
#   - email  : the account's root email (plus-addressing works: you+log-archive@...). @example.com is refused by the factory
#   - monthly_budget_usd : monthly cost budget (USD); alerts at 50/80/100 % actual and 100 % forecast go to the account's email.
#                  For the management account (the payer) it covers the whole organization, so keep it low.
#   - alias  : the IAM account alias (set by governance/account-baseline)
#   - owner  : owning team
#   - data_classification : public | internal | confidential
#   - ci     : true = the pipeline plans (and, on main, applies through the account's GitHub Environment) this account's stacks.
#              An account is only run once it has a live folder and a real (non-placeholder) id, see generate_account_matrix.py
#   - create : true = the factory manages this account (an account you made by hand must be IMPORTED first);
#              false = a placeholder or the management account: never created

locals {
  local_override = try(read_terragrunt_config("${get_repo_root()}/iac-live-repo/_config/accounts.local.hcl"), { locals = { accounts = {} } })
  local_accounts = try(local.local_override.locals.accounts, {})

  base_accounts = {
    management = {
      id                  = "000000000000"
      ou                  = "Root"
      env                 = "global"
      email               = "aws+management@example.com"
      create              = false
      monthly_budget_usd  = 50
      ci                  = false
      alias               = "ok-karthik-management"
      owner               = "platform-team" # TODO(owner): real owning team
      data_classification = "internal"      # TODO(owner): confirm (public | internal | confidential)
    }
    log-archive = {
      id                  = "000000000001"
      ou                  = "Security"
      env                 = "global"
      email               = "aws+log-archive@example.com"
      create              = true
      monthly_budget_usd  = 10
      ci                  = false
      alias               = "ok-karthik-log-archive"
      owner               = "platform-team" # TODO(owner): real owning team
      data_classification = "confidential"  # audit logs
    }
    security-tooling = {
      id                  = "000000000002"
      ou                  = "Security"
      env                 = "global"
      email               = "aws+security@example.com"
      create              = true
      monthly_budget_usd  = 20
      ci                  = false
      alias               = "ok-karthik-security-tooling"
      owner               = "platform-team" # TODO(owner): real owning team
      data_classification = "confidential"  # TODO(owner): confirm (public | internal | confidential)
    }
    network-hub = {
      id                  = "000000000003"
      ou                  = "Infrastructure"
      env                 = "global"
      email               = "aws+network@example.com"
      create              = true
      monthly_budget_usd  = 50
      ci                  = false
      alias               = "ok-karthik-network-hub"
      owner               = "platform-team" # TODO(owner): real owning team
      data_classification = "internal"      # network infrastructure, not application data
    }
    shared-services = {
      id                  = "000000000004"
      ou                  = "Infrastructure"
      env                 = "global"
      email               = "aws+shared@example.com"
      create              = true
      monthly_budget_usd  = 30
      ci                  = false
      alias               = "ok-karthik-shared-services"
      owner               = "platform-team" # TODO(owner): real owning team
      data_classification = "internal"      # shared network infrastructure, not application data
    }
    observability = {
      id                  = "000000000007"
      ou                  = "Infrastructure"
      env                 = "global"
      email               = "aws+observability@example.com"
      create              = true
      monthly_budget_usd  = 30
      ci                  = false
      alias               = "ok-karthik-observability"
      owner               = "platform-team" # TODO(owner): real owning team
      data_classification = "internal"      # metrics and logs of the platform (may contain personal data: review before widening access)
    }
    workloads-dev = {
      id                  = "000000000005"
      ou                  = "NonProd"
      env                 = "dev"
      email               = "aws+workloads-dev@example.com"
      create              = true
      monthly_budget_usd  = 100
      ci                  = true
      alias               = "ok-karthik-workloads-dev"
      owner               = "platform-team" # TODO(owner): real owning team
      data_classification = "internal"      # TODO(owner): confirm (public | internal | confidential)
    }
    workloads-prod = {
      id                  = "000000000006"
      ou                  = "Prod"
      env                 = "prod"
      email               = "aws+workloads-prod@example.com"
      create              = false
      monthly_budget_usd  = 100
      ci                  = true
      alias               = "ok-karthik-workloads-prod"
      owner               = "platform-team" # TODO(owner): real owning team
      data_classification = "confidential"  # TODO(owner): confirm (public | internal | confidential)
    }
  }

  accounts = {
    for name, base in local.base_accounts :
    name => merge(base, try(local.local_accounts[name], {}))
  }
}
