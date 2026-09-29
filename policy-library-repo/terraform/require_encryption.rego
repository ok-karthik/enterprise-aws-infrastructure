package main

import rego.v1

# Encryption at rest for EC2 volumes that Checkov does not check here (PLAN 8.10).
#
# Everything else (RDS, standalone EBS volumes, S3, SQS, SNS) is enforced by Checkov: CKV_AWS_16, CKV_AWS_3,
# CKV_AWS_19, CKV_AWS_27, CKV_AWS_26. Two cases had no Checkov equivalent, so they stay here:
#   - aws_instance root/extra block devices: Checkov's check for this (CKV_AWS_8) is skipped repo-wide in
#     .checkov.yaml, so nothing else covers it;
#   - aws_launch_template block device mappings: Checkov has no check for them.

deny contains msg if {
	some r in changed_resources
	r.type == "aws_instance"
	some kind in ["root_block_device", "ebs_block_device"]
	some dev in as_list(object.get(r.change.after, kind, []))
	object.get(dev, "encrypted", false) != true
	msg := sprintf("Governance Violation: '%v' has an unencrypted %v. Set encrypted = true.", [r.address, kind])
}

# In a launch template, `encrypted` is a string ("true"), so compare as text.
deny contains msg if {
	some r in changed_resources
	r.type == "aws_launch_template"
	some mapping in as_list(object.get(r.change.after, "block_device_mappings", []))
	some ebs in as_list(object.get(mapping, "ebs", []))
	sprintf("%v", [object.get(ebs, "encrypted", false)]) != "true"
	msg := sprintf("Governance Violation: launch template '%v' maps an EBS volume (%v) without encrypted = true.", [r.address, object.get(mapping, "device_name", "?")])
}
