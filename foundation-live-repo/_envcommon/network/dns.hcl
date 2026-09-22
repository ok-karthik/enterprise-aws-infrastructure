# Common configuration for DNS (PLAN 5.5), applied in network-hub, per region. Applied by the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.dns
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/network/dns" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/network/dns?ref=${local.module_version}"

  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region  = local.region_vars.locals.aws_region

  registry               = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
  log_archive_account_id = local.registry.locals.accounts["log-archive"].id
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
