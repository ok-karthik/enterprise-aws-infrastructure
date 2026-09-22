locals {
  env          = "global"
  cluster_name = ""

  # --- MODULE VERSIONS ---
  module_versions = {
    organization        = "organization-v1.0.0"
    bootstrap_stacksets = "bootstrap-stacksets-v1.0.0"
    account_factory     = "account-factory-v1.0.0"
    account_baseline    = "account-baseline-v1.0.0"
    budgets             = "budgets-v1.0.0"
    identity_center     = "identity-center-v1.0.0"
    break_glass_alerts  = "break-glass-alerts-v1.0.0"
    org_cloudtrail      = "org-cloudtrail-v1.0.0"
  }
}
