locals {
  env          = "global"
  cluster_name = ""

  # --- MODULE VERSIONS ---
  module_versions = {
    ipam              = "ipam-v1.0.0"
    transit_gateway   = "transit-gateway-v1.0.0"
    inspection_egress = "inspection-egress-v1.0.0"
    dns               = "dns-v1.0.0"
  }
}
