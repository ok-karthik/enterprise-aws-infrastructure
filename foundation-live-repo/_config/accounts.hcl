# Account registry: the single source of truth for which AWS accounts exist. The account factory
# vends the entries with create = true; scripts/check-account-registry.sh fails CI if any
# account.hcl uses an ID that is not listed here.
#
# TODO(owner): every id / email marked below is a placeholder. Fill in the real ones.
#   - id     : the 12-digit account ID
#   - ou     : OU name from the organization module ("Root" = directly under the root, only the management account)
#   - env    : global | dev | staging | prod
#   - email  : the account's root email (plus-addressing works: you+log-archive@...). @example.com is refused by the factory
#   - create : true = the factory manages this account (an account you made by hand must be IMPORTED first);
#              false = a placeholder or the management account: never created
locals {
  accounts = {
    management = {
      id     = "954171757349"
      ou     = "Root"
      env    = "global"
      email  = "aws+management@example.com" # TODO(owner): not used, the management account is never created here
      create = false
    }
    log-archive = {
      id     = "000000000001" # TODO(owner): real account ID
      ou     = "Security"
      env    = "global"
      email  = "aws+log-archive@example.com" # TODO(owner): real root email
      create = true
    }
    security-tooling = {
      id     = "000000000002" # TODO(owner): real account ID
      ou     = "Security"
      env    = "global"
      email  = "aws+security@example.com" # TODO(owner): real root email
      create = true
    }
    network-hub = {
      id     = "000000000003" # placeholder until needed (PLAN 5.x)
      ou     = "Infrastructure"
      env    = "global"
      email  = "aws+network@example.com"
      create = false
    }
    shared-services = {
      id     = "000000000004" # placeholder until needed
      ou     = "Infrastructure"
      env    = "global"
      email  = "aws+shared@example.com"
      create = false
    }
    workloads-dev = {
      id     = "000000000005" # TODO(owner): the existing "Account A" workload account
      ou     = "NonProd"
      env    = "dev"
      email  = "aws+workloads-dev@example.com" # TODO(owner): real root email
      create = true
    }
    workloads-prod = {
      id     = "000000000006" # placeholder until needed
      ou     = "Prod"
      env    = "prod"
      email  = "aws+workloads-prod@example.com"
      create = false
    }
  }
}
