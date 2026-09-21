locals {
  env          = "global"
  cluster_name = ""

  # --- MODULE VERSIONS ---
  module_versions = {
    organization        = "organization-v1.0.0"
    bootstrap_stacksets = "bootstrap-stacksets-v1.0.0"
    account_factory     = "account-factory-v1.0.0"
    account_baseline    = "account-baseline-v1.0.0"
  }
}
