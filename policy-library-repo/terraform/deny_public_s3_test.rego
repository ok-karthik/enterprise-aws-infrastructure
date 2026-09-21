package main

import rego.v1

s3_pab(after) := {"resource_changes": [{
	"address": "aws_s3_bucket_public_access_block.this",
	"type": "aws_s3_bucket_public_access_block",
	"change": {"actions": ["create"], "after": after},
}]}

s3_policy(doc) := {"resource_changes": [{
	"address": "aws_s3_bucket_policy.this",
	"type": "aws_s3_bucket_policy",
	"change": {"actions": ["create"], "after": {"policy": json.marshal(doc)}},
}]}

test_public_s3_all_flags_on if {
	count(deny) == 0 with input as s3_pab({"block_public_acls": true, "block_public_policy": true, "ignore_public_acls": true, "restrict_public_buckets": true})
}

test_public_s3_one_flag_off_denied if {
	some m in deny with input as s3_pab({"block_public_acls": true, "block_public_policy": false, "ignore_public_acls": true, "restrict_public_buckets": true})
	contains(m, "block_public_policy")
}

test_public_s3_omitted_flag_denied if {
	count(deny) > 0 with input as s3_pab({"block_public_acls": true, "block_public_policy": true, "ignore_public_acls": true})
}

test_public_s3_policy_star_principal_denied if {
	count(deny) > 0 with input as s3_policy({"Statement": [{"Effect": "Allow", "Principal": "*", "Action": "s3:GetObject", "Resource": "*"}]})
}

test_public_s3_policy_aws_star_principal_denied if {
	count(deny) > 0 with input as s3_policy({"Statement": {"Effect": "Allow", "Principal": {"AWS": "*"}, "Action": "s3:GetObject", "Resource": "*"}})
}

test_public_s3_policy_star_with_org_condition_allowed if {
	count(deny) == 0 with input as s3_policy({"Statement": [{
		"Effect": "Allow",
		"Principal": "*",
		"Action": "s3:GetObject",
		"Resource": "*",
		"Condition": {"StringEquals": {"aws:PrincipalOrgID": "o-abc123"}},
	}]})
}

test_public_s3_policy_deny_statement_allowed if {
	count(deny) == 0 with input as s3_policy({"Statement": [{"Effect": "Deny", "Principal": "*", "Action": "s3:*", "Resource": "*", "Condition": {"Bool": {"aws:SecureTransport": "false"}}}]})
}

test_public_s3_policy_specific_principal_allowed if {
	count(deny) == 0 with input as s3_policy({"Statement": [{"Effect": "Allow", "Principal": {"AWS": "arn:aws:iam::111122223333:root"}, "Action": "s3:GetObject", "Resource": "*"}]})
}
