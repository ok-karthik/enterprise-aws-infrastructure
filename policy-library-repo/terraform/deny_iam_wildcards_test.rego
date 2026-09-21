package main

import rego.v1

iam_input(type, attr, name, doc) := {"resource_changes": [{
	"address": concat(".", [type, name]),
	"type": type,
	"change": {"actions": ["create"], "after": {"name": name, attr: json.marshal(doc)}},
}]}

test_iam_wildcards_star_star_denied if {
	some m in deny with input as iam_input("aws_iam_policy", "policy", "god", {"Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]})
	contains(m, "aws_iam_policy.god")
}

test_iam_wildcards_lists_denied if {
	count(deny) > 0 with input as iam_input("aws_iam_role_policy", "policy", "god", {"Statement": [{"Effect": "Allow", "Action": ["*"], "Resource": ["*"]}]})
}

test_iam_wildcards_single_statement_object_denied if {
	count(deny) > 0 with input as iam_input("aws_iam_policy", "policy", "god", {"Statement": {"Effect": "Allow", "Action": "*", "Resource": "*"}})
}

test_iam_wildcards_sso_inline_policy_denied if {
	count(deny) > 0 with input as iam_input("aws_ssoadmin_permission_set_inline_policy", "inline_policy", "god", {"Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]})
}

test_iam_wildcards_scoped_action_allowed if {
	count(deny) == 0 with input as iam_input("aws_iam_policy", "policy", "ok", {"Statement": [{"Effect": "Allow", "Action": "s3:ListAllMyBuckets", "Resource": "*"}]})
}

test_iam_wildcards_scoped_resource_allowed if {
	count(deny) == 0 with input as iam_input("aws_iam_policy", "policy", "ok", {"Statement": [{"Effect": "Allow", "Action": "*", "Resource": "arn:aws:s3:::platform-*"}]})
}

test_iam_wildcards_deny_statement_allowed if {
	count(deny) == 0 with input as iam_input("aws_iam_policy", "policy", "guard", {"Statement": [{"Effect": "Deny", "Action": "*", "Resource": "*"}]})
}

test_iam_wildcards_allowlisted_boundary_allowed if {
	count(deny) == 0 with input as iam_input("aws_iam_policy", "policy", "github-actions-apply-boundary", {"Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]})
}

test_iam_wildcards_workload_boundary_allowed if {
	count(deny) == 0 with input as iam_input("aws_iam_policy", "policy", "platform-workload-boundary", {"Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]})
}
