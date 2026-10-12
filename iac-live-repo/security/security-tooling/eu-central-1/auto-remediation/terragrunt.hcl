# The auto-remediation Lambda (PLAN 4.9): removes open SSH/RDP security group rules; applied in security-tooling by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/security/auto-remediation"
}

# Auto-remediation Lambda and its central event bus. Apply AFTER security/security-alerts (this stack depends
# on its SNS topic) and with the real organization id in _config/organization.hcl. Every member account that
# should be protected also needs governance/account-baseline applied WITH security_remediation_lambda_role_arn
# set to this Lambda's role ARN (this module's output lambda_function_arn's role, i.e. the "<function>-lambda"
# role, not the function itself) and its OWN EventBridge forwarding rule to this module's event bus -- neither
# of which this stack creates by itself. See both modules' READMEs.
dependency "security_alerts" {
  config_path = "../security-alerts"

  mock_outputs = {
    topic_arn = "arn:aws:sns:eu-central-1:222233334444:security-alerts-alerts"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  organization_id = include.root.locals.organization.organization_id
  alert_topic_arn = dependency.security_alerts.outputs.topic_arn

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
