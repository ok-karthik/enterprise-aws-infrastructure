package main

import rego.v1

# 1. Block Public Access flags must all be true. An omitted flag defaults to false in the AWS
#    provider, so a missing flag is a violation too.
pab_flags := ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]

deny contains msg if {
	some r in changed_resources
	r.type == "aws_s3_bucket_public_access_block"
	some flag in pab_flags
	object.get(r.change.after, flag, false) != true
	msg := sprintf("Governance Violation: '%v' does not enable %v. S3 Block Public Access must be fully on.", [r.address, flag])
}

# 2. Bucket policies must not grant access to everyone, unless limited to the organization.
s3_public_principal(p) if p == "*"

s3_public_principal(p) if p.AWS == "*"

s3_public_principal(p) if "*" in as_list(p.AWS)

s3_has_org_condition(stmt) if {
	some _, values in stmt.Condition
	values["aws:PrincipalOrgID"]
}

deny contains msg if {
	some r in changed_resources
	r.type == "aws_s3_bucket_policy"
	is_string(r.change.after.policy)
	doc := json.unmarshal(r.change.after.policy)
	some stmt in as_array(doc.Statement)
	stmt.Effect == "Allow"
	s3_public_principal(stmt.Principal)
	not s3_has_org_condition(stmt)
	msg := sprintf("Governance Violation: bucket policy '%v' allows Principal \"*\" without an aws:PrincipalOrgID condition.", [r.address])
}
