locals {
  env          = "global"
  cluster_name = ""

  # --- MODULE VERSIONS ---
  module_versions = {
    access_analyzer  = "access-analyzer-v1.1.0"
    threat_detection = "threat-detection-v1.0.0"
    security_alerts  = "security-alerts-v1.0.0"
    auto_remediation = "auto-remediation-v1.0.0"
    firewall_manager = "firewall-manager-v1.0.0"
    waf_logging      = "waf-logging-v1.0.0"
    shield_advanced  = "shield-advanced-v1.0.0"
  }
}
