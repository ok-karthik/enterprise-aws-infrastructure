package main

import rego.v1

# No IAM policy may Allow every action on every resource ("god mode").
# Resources holding a policy document, and the attribute the JSON lives in:
iam_policy_attribute := {
	"aws_iam_policy": "policy",
	"aws_iam_role_policy": "policy",
	"aws_iam_user_policy": "policy",
	"aws_iam_group_policy": "policy",
	"aws_ssoadmin_permission_set_inline_policy": "inline_policy",
}

# Policies that are allowed to be Action "*" / Resource "*", by name. Keep this list tiny and
# say why: github-actions-apply-boundary is a permissions boundary (it only ever narrows).
wildcard_policy_allowlist := {"github-actions-apply-boundary"}

iam_policy_documents contains doc if {
	some r in changed_resources
	attr := iam_policy_attribute[r.type]
	raw := r.change.after[attr]
	is_string(raw)
	doc := {
		"address": r.address,
		"name": object.get(r.change.after, "name", ""),
		"policy": json.unmarshal(raw),
	}
}

deny contains msg if {
	some doc in iam_policy_documents
	not doc.name in wildcard_policy_allowlist
	some stmt in as_array(doc.policy.Statement)
	stmt.Effect == "Allow"
	"*" in as_array(stmt.Action)
	"*" in as_array(stmt.Resource)
	msg := sprintf("Governance Violation: IAM policy '%v' allows Action \"*\" on Resource \"*\". Scope it to the actions and resources it needs.", [doc.address])
}
