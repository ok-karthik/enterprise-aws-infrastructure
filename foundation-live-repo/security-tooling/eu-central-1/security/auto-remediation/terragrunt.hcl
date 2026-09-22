include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/security/auto-remediation.hcl"
  expose = true
}

# Auto-remediation Lambda and its central event bus. Apply AFTER security/security-alerts (this leaf depends
# on its SNS topic) and with the real organization id in _config/organization.hcl. Every member account that
# should be protected also needs governance/account-baseline applied WITH security_remediation_lambda_role_arn
# set to this Lambda's role ARN (this module's output lambda_function_arn's role, i.e. the "<function>-lambda"
# role, not the function itself) and its OWN EventBridge forwarding rule to this module's event bus — neither
# of which this leaf creates by itself. See both modules' READMEs.
inputs = {}
