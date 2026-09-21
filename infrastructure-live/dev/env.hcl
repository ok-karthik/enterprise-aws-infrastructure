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
}
