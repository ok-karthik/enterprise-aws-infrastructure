locals {
  env          = "prod"
  cluster_name = "main-eks-prod"

  # --- COST OPTIMIZATION: Dormant Prod ---
  min_size           = 0
  desired_size       = 0
  enable_nat_gateway = false
  single_nat_gateway = false # one NAT per AZ, so a single AZ outage does not cut all prod egress (only takes effect when enable_nat_gateway = true)

  # --- SECURITY: EKS public API endpoint allow-list ---
  # Empty = private endpoint only (reach it from inside the VPC, e.g. SSM / VPN).
  # To use kubectl from a laptop, list explicit CIDRs, e.g. ["203.0.113.7/32"]. Never 0.0.0.0/0.
  api_allowed_cidrs = [] # TODO(owner): add your office/VPN egress CIDR(s) if you need public kubectl
}
