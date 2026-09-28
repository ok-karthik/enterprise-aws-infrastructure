locals {
  env          = "global"
  cluster_name = ""

  # --- MODULE VERSIONS ---
  module_versions = {
    organization        = "organization-v2.1.0"
    bootstrap_stacksets = "bootstrap-stacksets-v2.1.0"
    account_factory     = "account-factory-v1.0.0"
    account_baseline    = "account-baseline-v1.1.0"
    budgets             = "budgets-v1.0.0"
    identity_center     = "identity-center-v1.1.0"
    break_glass_alerts  = "break-glass-alerts-v1.1.0"
    org_cloudtrail      = "org-cloudtrail-v1.0.0"
    security_alerts     = "security-alerts-v1.0.0"
    data_perimeter      = "data-perimeter-v1.0.0"
  }
}
