locals {
  env          = "global"
  cluster_name = ""

  # --- MODULE VERSIONS ---
  module_versions = {
    access_analyzer  = "access-analyzer-v1.0.0"
    threat_detection = "threat-detection-v1.0.0"
    security_alerts  = "security-alerts-v1.0.0"
  }
}
