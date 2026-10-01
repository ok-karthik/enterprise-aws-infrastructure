include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/observability/guardrail-signals.hcl"
  expose = true
}

# Alarms on the organization CloudTrail (covers every member account). Needs the org-cloudtrail and security-alerts
# stacks applied in this account first: it reads the trail's log group and the alert topic from them.
dependency "org_cloudtrail" {
  config_path = "${get_terragrunt_dir()}/../../security/org-cloudtrail"

  mock_outputs = {
    cloudwatch_log_group_name = "/aws/cloudtrail/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

dependency "security_alerts" {
  config_path = "${get_terragrunt_dir()}/../../security/security-alerts"

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
