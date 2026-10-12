# The "are the guardrails on?" alarms (PLAN 9.3) on the organization CloudTrail log group, applied in the management account by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/observability/guardrail-signals"
}

# Alarms on the organization CloudTrail (covers every member account). Needs the org-cloudtrail and security-alerts
# stacks applied in this account first: it reads the trail's log group and the alert topic from them.
dependency "org_cloudtrail" {
  config_path = "../org-cloudtrail"

  mock_outputs = {
    cloudwatch_log_group_name = "/aws/cloudtrail/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

dependency "security_alerts" {
  config_path = "../security-alerts"

  mock_outputs = {
    topic_arn = "arn:aws:sns:eu-central-1:000000000000:security-alerts-alerts"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  create_alarms   = true
  log_group_name  = dependency.org_cloudtrail.outputs.cloudwatch_log_group_name
  alarm_topic_arn = dependency.security_alerts.outputs.topic_arn

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
