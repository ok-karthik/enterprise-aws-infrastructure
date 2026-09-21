package main

import rego.v1

stackset_input(name, params) := {"resource_changes": [{
	"address": "aws_cloudformation_stack_set.this[\"x\"]",
	"type": "aws_cloudformation_stack_set",
	"change": {"actions": ["create"], "after": {"name": name, "parameters": params}},
}]}

test_member_org_admin_false_allowed if {
	count(deny) == 0 with input as stackset_input("bootstrap-nonprod", {"GitHubEnvironment": "dev", "AllowOrganizationsAdmin": "false"})
}

test_member_org_admin_omitted_allowed if {
	count(deny) == 0 with input as stackset_input("bootstrap-nonprod", {"GitHubEnvironment": "dev"})
}

test_member_org_admin_true_denied if {
	some m in deny with input as stackset_input("bootstrap-nonprod", {"GitHubEnvironment": "dev", "AllowOrganizationsAdmin": "true"})
	contains(m, "AllowOrganizationsAdmin")
}

test_member_stackset_wrong_name_denied if {
	some m in deny with input as stackset_input("platform-member-bootstrap", {"GitHubEnvironment": "dev", "AllowOrganizationsAdmin": "false"})
	contains(m, "bootstrap-*")
}

test_unrelated_stackset_ignored if {
	count(deny) == 0 with input as stackset_input("something-else", {"Foo": "bar", "AllowOrganizationsAdmin": "true"})
}
