# Org-wide IPAM (PLAN 5.1), applied in network-hub: a top-level pool, one regional pool per region (carved
# from the top-level pool), and prod/nonprod env pools under each regional pool. The regional pools are
# shared with the Workloads OU through RAM, so network/vpc in a workload account can request a CIDR from
# them (var.ipv4_ipam_pool_id) instead of hardcoding one.
#
# RAM sharing with an entire OU needs "sharing with AWS Organizations" turned on for the organization
# (aws_ram_sharing_with_organization) -- a one-time, organization-wide setting, not scoped to one resource
# share, so it does not belong in this module. Turn it on once (owner step, console or a single resource
# elsewhere) before the first apply here.

locals {
  # var.organization_id is not an argument any resource here takes (RAM sharing to an OU ARN already scopes
  # to that OU's organization); it is recorded as a tag instead, so the org this IPAM belongs to is visible
  # on every resource, and the required, validated variable has a real use.
  tags = merge({ OrganizationId = var.organization_id }, var.tags)
}

resource "aws_vpc_ipam" "this" {
  description        = "Platform-wide IPAM (PLAN 5.1)"
  enable_private_gua = false

  dynamic "operating_regions" {
    for_each = var.operating_regions
    content {
      region_name = operating_regions.value
    }
  }

  tags = local.tags
}

resource "aws_vpc_ipam_pool" "top_level" {
  description    = "Top-level pool: all platform IPv4 space"
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.this.private_default_scope_id
  locale         = "None" # top-level pools are not tied to one region

  tags = local.tags
}

resource "aws_vpc_ipam_pool_cidr" "top_level" {
  ipam_pool_id = aws_vpc_ipam_pool.top_level.id
  cidr         = var.top_level_cidr
}

resource "aws_vpc_ipam_pool" "regional" {
  for_each = var.regional_pools

  description         = "Regional pool: ${each.key}"
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  locale              = each.value.locale
  source_ipam_pool_id = aws_vpc_ipam_pool.top_level.id

  tags = local.tags
}

resource "aws_vpc_ipam_pool_cidr" "regional" {
  for_each = var.regional_pools

  ipam_pool_id = aws_vpc_ipam_pool.regional[each.key].id
  cidr         = each.value.cidr

  depends_on = [aws_vpc_ipam_pool_cidr.top_level]
}

locals {
  # "<region>/prod" and "<region>/nonprod" for every regional pool, with each env's netmask length.
  env_pools = merge([
    for region, pool in var.regional_pools : {
      "${region}/prod"    = { region = region, netmask_length = var.prod_env_netmask_length }
      "${region}/nonprod" = { region = region, netmask_length = var.nonprod_env_netmask_length }
    }
  ]...)
}

resource "aws_vpc_ipam_pool" "env" {
  for_each = local.env_pools

  description         = "Env pool: ${each.key}"
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  locale              = each.value.region
  source_ipam_pool_id = aws_vpc_ipam_pool.regional[each.value.region].id

  allocation_default_netmask_length = each.value.netmask_length
  allocation_max_netmask_length     = 28
  allocation_min_netmask_length     = each.value.netmask_length

  tags = local.tags
}

resource "aws_vpc_ipam_pool_cidr" "env" {
  for_each = local.env_pools

  ipam_pool_id   = aws_vpc_ipam_pool.env[each.key].id
  netmask_length = each.value.netmask_length

  depends_on = [aws_vpc_ipam_pool_cidr.regional]
}

# ------------------------------------------------------------------------------
# RAM: share the env pools (not the regional/top-level pools -- workload accounts should only ever
# request from their own env's pool) with the Workloads OU.
# ------------------------------------------------------------------------------
resource "aws_ram_resource_share" "pools" {
  name                      = "ipam-env-pools"
  allow_external_principals = false

  tags = local.tags
}

resource "aws_ram_resource_association" "pools" {
  for_each = aws_vpc_ipam_pool.env

  resource_arn       = each.value.arn
  resource_share_arn = aws_ram_resource_share.pools.arn
}

resource "aws_ram_principal_association" "workloads_ou" {
  principal          = var.workloads_ou_arn
  resource_share_arn = aws_ram_resource_share.pools.arn
}
