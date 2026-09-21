package main

import rego.v1

admin_attach(type, address, after) := {"resource_changes": [{
	"address": address,
	"type": type,
	"change": {"actions": ["create"], "after": after},
}]}

test_admin_attach_ci_apply_role_allowed if {
	count(deny) == 0 with input as admin_attach("aws_iam_role_policy_attachment", "module.r.aws_iam_role_policy_attachment.this[\"AdministratorAccess\"]", {"role": "github-actions-apply", "policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"})
}

test_admin_attach_break_glass_role_allowed if {
	count(deny) == 0 with input as admin_attach("aws_iam_role_policy_attachment", "aws_iam_role_policy_attachment.x", {"role": "break-glass-admin", "policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"})
}

test_admin_attach_readonly_allowed_anywhere if {
	count(deny) == 0 with input as admin_attach("aws_iam_role_policy_attachment", "aws_iam_role_policy_attachment.x", {"role": "some-app", "policy_arn": "arn:aws:iam::aws:policy/ReadOnlyAccess"})
}

test_admin_attach_other_role_denied if {
	some m in deny with input as admin_attach("aws_iam_role_policy_attachment", "aws_iam_role_policy_attachment.x", {"role": "app-role", "policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"})
	contains(m, "app-role")
}

test_admin_attach_iam_full_access_denied if {
	count(deny) > 0 with input as admin_attach("aws_iam_role_policy_attachment", "aws_iam_role_policy_attachment.x", {"role": "ack-hub-controller-access", "policy_arn": "arn:aws:iam::aws:policy/IAMFullAccess"})
}

test_admin_attach_unknown_role_name_denied if {
	count(deny) > 0 with input as admin_attach("aws_iam_role_policy_attachment", "aws_iam_role_policy_attachment.x", {"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"})
}

test_admin_attach_managed_policy_arns_on_role_denied if {
	count(deny) > 0 with input as admin_attach("aws_iam_role", "aws_iam_role.x", {"name": "app", "managed_policy_arns": ["arn:aws:iam::aws:policy/AdministratorAccess"]})
}

test_admin_attach_legacy_policy_attachment_to_user_denied if {
	count(deny) > 0 with input as admin_attach("aws_iam_policy_attachment", "aws_iam_policy_attachment.x", {"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess", "users": ["bob"], "roles": [], "groups": []})
}

test_admin_attach_permission_set_denied_unless_break_glass if {
	count(deny) > 0 with input as admin_attach("aws_ssoadmin_managed_policy_attachment", "aws_ssoadmin_managed_policy_attachment.platform_engineer", {"managed_policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"})
	count(deny) == 0 with input as admin_attach("aws_ssoadmin_managed_policy_attachment", "aws_ssoadmin_managed_policy_attachment.break_glass_admin[0]", {"managed_policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"})
}

test_admin_attach_ignores_deletes if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "aws_iam_role_policy_attachment.old",
		"type": "aws_iam_role_policy_attachment",
		"change": {"actions": ["delete"], "after": null, "before": {"role": "x", "policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"}},
	}]}
}
