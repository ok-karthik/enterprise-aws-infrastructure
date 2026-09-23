include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/network/inspection-egress.hcl"
  expose = true
}

# Central egress/inspection VPC for eu-west-1. Apply AFTER network/transit-gateway in this same region (this leaf
# depends on its transit_gateway_id and route_table_ids output) and after security/log-archive's first apply
# (its bucket policy must already trust delivery.logs.amazonaws.com, which it does by default). See the
# module README before relying on the firewall_status attachment lookup against real AWS.
inputs = {}
