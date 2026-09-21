package main

import rego.v1

# Only the CI apply role and break-glass roles may hold admin-level managed policies.
# Anything else is a route to standing admin (see PLAN 0.3, 0.6).

admin_policy_arns := {
	"arn:aws:iam::aws:policy/AdministratorAccess",
	"arn:aws:iam::aws:policy/IAMFullAccess",
}

admin_allowed_role_prefixes := ["github-actions-apply", "break-glass"]

admin_role_allowed(name) if {
	some prefix in admin_allowed_role_prefixes
	startswith(name, prefix)
}

# aws_iam_role_policy_attachment (also what terraform-aws-modules/iam creates)
# A role name that is unknown at plan time counts as "not allowed": fail closed.
deny contains msg if {
	some r in changed_resources
	r.type == "aws_iam_role_policy_attachment"
	r.change.after.policy_arn in admin_policy_arns
	role := object.get(r.change.after, "role", "")
	not admin_role_allowed(role)
	msg := sprintf("Governance Violation: '%v' attaches %v to role '%v'. Only roles named github-actions-apply* or break-glass* may hold admin-level policies.", [r.address, r.change.after.policy_arn, role])
}

# aws_iam_role.managed_policy_arns (deprecated, still used)
deny contains msg if {
	some r in changed_resources
	r.type == "aws_iam_role"
	some arn in as_list(object.get(r.change.after, "managed_policy_arns", []))
	arn in admin_policy_arns
	name := object.get(r.change.after, "name", "")
	not admin_role_allowed(name)
	msg := sprintf("Governance Violation: role '%v' (%v) carries %v. Only roles named github-actions-apply* or break-glass* may hold admin-level policies.", [name, r.address, arn])
}

# aws_iam_policy_attachment (legacy): roles are checked by name, users and groups never allowed
deny contains msg if {
	some r in changed_resources
	r.type == "aws_iam_policy_attachment"
	r.change.after.policy_arn in admin_policy_arns
	some role in as_list(object.get(r.change.after, "roles", []))
	not admin_role_allowed(role)
	msg := sprintf("Governance Violation: '%v' attaches %v to role '%v'. Only roles named github-actions-apply* or break-glass* may hold admin-level policies.", [r.address, r.change.after.policy_arn, role])
}

deny contains msg if {
	some r in changed_resources
	r.type == "aws_iam_policy_attachment"
	r.change.after.policy_arn in admin_policy_arns
	some kind in ["users", "groups"]
	count(as_list(object.get(r.change.after, kind, []))) > 0
	msg := sprintf("Governance Violation: '%v' attaches %v to IAM %v. Admin-level policies may only be held by github-actions-apply* or break-glass* roles.", [r.address, r.change.after.policy_arn, kind])
}

# IAM Identity Center: a permission set attachment only knows the permission set's ARN (unknown
# at plan time), so the address is what we can check: the break-glass permission set is the one
# place AdministratorAccess is allowed.
deny contains msg if {
	some r in changed_resources
	r.type == "aws_ssoadmin_managed_policy_attachment"
	r.change.after.managed_policy_arn in admin_policy_arns
	not contains(r.address, "break_glass")
	msg := sprintf("Governance Violation: '%v' attaches %v to a permission set. Only the break-glass permission set may carry admin-level policies.", [r.address, r.change.after.managed_policy_arn])
}
