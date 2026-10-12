# DNS (PLAN 5.5), applied in network-hub, per region, by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/network/dns"
}

# DNS for eu-central-1. Apply after the real Workloads OU ARN and log-archive account id are filled in (below).
# See the module README for the two Checkov skips that need a us-east-1 follow-up (DNSSEC signing,
# public-zone query logging), not built by this stack either.
locals {
  aws_region             = include.root.locals.aws_region
  log_archive_account_id = include.root.locals.registry["log-archive"].id
}

inputs = {
  vpc_cidr = "172.16.48.0/24" # distinct from IPAM's 10.0.0.0/8, inspection-egress's 172.16.0.0/20, central-endpoints' 172.16.16.0/24
  azs      = ["${local.aws_region}a", "${local.aws_region}b"]

  # TODO(owner): the real Workloads OU ARN, once governance/organization is applied and imported.
  workloads_ou_arn = "arn:aws:organizations::000000000000:ou/o-0000000000/ou-0000-00000000"

  # security/log-archive's bucket_names["vpc_flow_logs"] naming contract (same bucket network/inspection-egress uses).
  query_log_destination_arn = "arn:aws:s3:::platform-vpc-flow-logs-${local.log_archive_account_id}-${local.aws_region}/dns"

  # TODO(owner): a real on-premises CIDR list and DNS forwarding rules, once there is a real peer
  # (network/transit-gateway's hybrid connectivity, PLAN 5.6). Empty means neither is configured yet.
  on_prem_cidr_blocks = []
  forwarding_rules    = {}

  # TODO(owner): the platform's real public root domain, and any workload account subdomains to delegate.
  # Empty means no public zone is created yet.
  root_domain          = ""
  delegated_subdomains = {}

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
