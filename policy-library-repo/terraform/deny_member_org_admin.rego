package main

import rego.v1

# Member-account bootstrap StackSets (identified by the GitHubEnvironment parameter of
# foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml):
#   1. must never pass AllowOrganizationsAdmin other than "false", or the apply role in every
#      member account could manage AWS Organizations;
#   2. must be named bootstrap-*, because the apply role's permissions boundary only protects
#      stacks named StackSet-bootstrap-*.

bootstrap_stack_sets contains r if {
	some r in changed_resources
	r.type == "aws_cloudformation_stack_set"
	is_object(r.change.after.parameters)
	"GitHubEnvironment" in object.keys(r.change.after.parameters)
}

deny contains msg if {
	some r in bootstrap_stack_sets
	object.get(r.change.after.parameters, "AllowOrganizationsAdmin", "false") != "false"
	msg := sprintf("Governance Violation: StackSet '%v' sets AllowOrganizationsAdmin to something other than \"false\". Member accounts must never be able to manage AWS Organizations.", [r.address])
}

deny contains msg if {
	some r in bootstrap_stack_sets
	not startswith(object.get(r.change.after, "name", ""), "bootstrap-")
	msg := sprintf("Governance Violation: StackSet '%v' must be named bootstrap-*, otherwise the apply role's boundary does not protect its stacks (StackSet-bootstrap-*).", [r.address])
}
