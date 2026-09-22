locals {
  env          = "global"
  cluster_name = ""

  # --- MODULE VERSIONS ---
  module_versions = {
    ipam            = "ipam-v1.0.0"
    transit_gateway = "transit-gateway-v1.0.0"
  }
}
