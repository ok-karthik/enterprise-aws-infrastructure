locals {
  env          = "dev"
  cluster_name = "main-eks-dev"

  # --- COST OPTIMIZATION: Active Dev ---
  min_size           = 1
  desired_size       = 1
  enable_nat_gateway = true
  single_nat_gateway = true # one shared NAT is fine for dev; an AZ outage only affects dev egress

  # --- SECURITY: EKS public API endpoint allow-list ---
  # Empty = private endpoint only (reach it from inside the VPC, e.g. SSM / VPN).
  # To use kubectl from a laptop, list explicit CIDRs, e.g. ["203.0.113.7/32"]. Never 0.0.0.0/0.
  api_allowed_cidrs = [] # TODO(owner): add your office/VPN egress CIDR(s) if you need public kubectl

  # --- MODULE VERSIONS: promote dev -> prod by bumping these pins, dev first ---
  # Release tags of iac-modules-repo/, one per module (<module>-vX.Y.Z). Renovate opens the PRs.
  module_versions = {
    vpc                 = "vpc-v1.0.0"
    eks                 = "eks-v1.0.0"
    account_baseline    = "account-baseline-v1.0.0"
    discovery_publisher = "discovery-publisher-v1.0.0"
    budgets             = "budgets-v1.0.0"
    break_glass_alerts  = "break-glass-alerts-v1.0.0"
  }
}
