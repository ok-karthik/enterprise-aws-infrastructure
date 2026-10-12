# The central egress/inspection VPC (PLAN 5.3), applied in network-hub, per region, by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/network/inspection-egress"
}

# Apply AFTER network/transit-gateway in this same region (this stack depends on its transit_gateway_id and
# route_table_ids output) and after security/log-archive's first apply (its bucket policy must already trust
# delivery.logs.amazonaws.com, which it does by default). See the module README before relying on the
# firewall_status attachment lookup against real AWS.
dependency "transit_gateway" {
  config_path = "../transit-gateway"

  mock_outputs = {
    transit_gateway_id = "tgw-mock0123456789abcdef"
    route_table_ids    = { prod = "tgw-rtb-mockprod", nonprod = "tgw-rtb-mocknonprod", shared = "tgw-rtb-mockshared", inspection = "tgw-rtb-mockinspection" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

# <prefix>-vpc-flow-logs-<log-archive account id>-<region>: the naming contract security/log-archive's
# bucket_names["vpc_flow_logs"] output builds too (see that module's README); computed here rather than
# read via a Terragrunt dependency so this stack does not need security/log-archive to exist in the same
# branch/checkout.
locals {
  aws_region              = include.root.locals.aws_region
  log_archive_account_id  = include.root.locals.registry["log-archive"].id
  log_archive_bucket_name = "platform-vpc-flow-logs-${local.log_archive_account_id}-${local.aws_region}"
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
