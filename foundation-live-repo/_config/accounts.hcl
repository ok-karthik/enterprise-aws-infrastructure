# Account registry: the single source of truth for which AWS accounts exist. The account factory
# vends the entries with create = true; scripts/check-account-registry.sh fails CI if any
# account.hcl uses an ID that is not listed here.
#
# TODO(owner): every id / email marked below is a placeholder. Fill in the real ones.
#   - id     : the 12-digit account ID
#   - ou     : OU name from the organization module ("Root" = directly under the root, only the management account)
#   - env    : global | dev | staging | prod
#   - email  : the account's root email (plus-addressing works: you+log-archive@...). @example.com is refused by the factory
#   - monthly_budget_usd : monthly cost budget (USD); alerts at 50/80/100 % actual and 100 % forecast go to the account's email.
#                  For the management account (the payer) it covers the whole organization, so keep it low.
#   - ci     : true = the pipeline plans (and, on main, applies through the account's GitHub Environment) this account's stacks.
#              An account is only run once it has a live folder and a real (non-placeholder) id, see generate_account_matrix.py
#   - create : true = the factory manages this account (an account you made by hand must be IMPORTED first);
#              false = a placeholder or the management account: never created
locals {
  accounts = {
    management = {
      id                 = "954171757349"
      ou                 = "Root"
      env                = "global"
      email              = "aws+management@example.com" # TODO(owner): not used, the management account is never created here
      create             = false
      monthly_budget_usd = 50    # TODO(owner): monthly budget in USD
      ci                 = false # TODO(owner): set true once the organization stack is imported and the placeholders are replaced
    }
    log-archive = {
      id                 = "000000000001" # TODO(owner): real account ID
      ou                 = "Security"
      env                = "global"
      email              = "aws+log-archive@example.com" # TODO(owner): real root email
      create             = true
      monthly_budget_usd = 10    # TODO(owner): monthly budget in USD
      ci                 = false # live folder exists (log archive, PLAN 4.1) but the id is still a placeholder
    }
    security-tooling = {
      id                 = "000000000002" # TODO(owner): real account ID
      ou                 = "Security"
      env                = "global"
      email              = "aws+security@example.com" # TODO(owner): real root email
      create             = true
      monthly_budget_usd = 20    # TODO(owner): monthly budget in USD
      ci                 = false # no live stack yet
    }
    network-hub = {
      id                 = "000000000003" # TODO(owner): real account ID
      ou                 = "Infrastructure"
      env                = "global"
      email              = "aws+network@example.com" # TODO(owner): real root email
      create             = true                      # PLAN 5.x is now being built; live folder exists, id is still a placeholder
      monthly_budget_usd = 50                        # TODO(owner): monthly budget in USD
      ci                 = false                     # no live stack yet
    }
    shared-services = {
      id                 = "000000000004" # TODO(owner): real account ID
      ou                 = "Infrastructure"
      env                = "global"
      email              = "aws+shared@example.com" # TODO(owner): real root email
      create             = true                     # PLAN 5.4/5.5 are now being built; live folder exists, id is still a placeholder
      monthly_budget_usd = 30                       # TODO(owner): monthly budget in USD
      ci                 = false                    # no live stack yet
    }
    workloads-dev = {
      id                 = "000000000005" # TODO(owner): the existing "Account A" workload account
      ou                 = "NonProd"
      env                = "dev"
      email              = "aws+workloads-dev@example.com" # TODO(owner): real root email
      create             = true
      monthly_budget_usd = 100 # TODO(owner): monthly budget in USD
      ci                 = true
    }
    workloads-prod = {
      id                 = "000000000006" # placeholder until needed
      ou                 = "Prod"
      env                = "prod"
      email              = "aws+workloads-prod@example.com"
      create             = false
      monthly_budget_usd = 100 # TODO(owner): monthly budget in USD
      ci                 = true
    }
  }
}
