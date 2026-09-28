# Common configuration for the central egress/inspection VPC (PLAN 5.3), applied in network-hub, per region.
# Applied by the owner, AFTER network/transit-gateway in the same region.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.inspection_egress
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/network/inspection-egress" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/network/inspection-egress?ref=${local.module_version}"

  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region  = local.region_vars.locals.aws_region

  # <prefix>-vpc-flow-logs-<log-archive account id>-<region>: the naming contract security/log-archive's
  # bucket_names["vpc_flow_logs"] output builds too (see that module's README); computed here rather than
  # read via a Terragrunt dependency so this leaf does not need security/log-archive to exist in the same
  # branch/checkout.
  registry                = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
  log_archive_account_id  = local.registry.locals.accounts["log-archive"].id
  log_archive_bucket_name = "platform-vpc-flow-logs-${local.log_archive_account_id}-${local.aws_region}"
}

dependency "transit_gateway" {
  config_path = "${get_terragrunt_dir()}/../transit-gateway"

  mock_outputs = {
    transit_gateway_id = "tgw-mock0123456789abcdef"
    route_table_ids    = { prod = "tgw-rtb-mockprod", nonprod = "tgw-rtb-mocknonprod", shared = "tgw-rtb-mockshared", inspection = "tgw-rtb-mockinspection" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  vpc_cidr = "172.16.0.0/20" # distinct from the IPAM top-level pool's 10.0.0.0/8 (network/ipam), no overlap
  azs      = ["${local.aws_region}a", "${local.aws_region}b"]

  transit_gateway_id        = dependency.transit_gateway.outputs.transit_gateway_id
  inspection_route_table_id = dependency.transit_gateway.outputs.route_table_ids["inspection"]

  # TODO(owner): a real starting allow-list. Package registries and base-image registries are common first
  # entries; everything else is dropped once a connection is established (STRICT_ORDER, see the module README).
  domain_allow_list = [
    "pypi.org", "files.pythonhosted.org",
    "registry.npmjs.org",
    "github.com", "raw.githubusercontent.com", "objects.githubusercontent.com",
    "registry-1.docker.io", "auth.docker.io", "production.cloudflare.docker.com",
    "public.ecr.aws",
  ]

  log_archive_bucket_name = local.log_archive_bucket_name

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
