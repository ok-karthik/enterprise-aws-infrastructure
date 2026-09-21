package main

import rego.v1

# Encryption at rest must be explicit, not left to defaults.

# RDS
deny contains msg if {
	some r in changed_resources
	r.type in {"aws_db_instance", "aws_rds_cluster"}
	object.get(r.change.after, "storage_encrypted", false) != true
	msg := sprintf("Governance Violation: '%v' must set storage_encrypted = true.", [r.address])
}

# EBS: standalone volumes, instance block devices, launch template mappings
deny contains msg if {
	some r in changed_resources
	r.type == "aws_ebs_volume"
	object.get(r.change.after, "encrypted", false) != true
	msg := sprintf("Governance Violation: EBS volume '%v' must set encrypted = true.", [r.address])
}

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

# S3: every bucket needs a server-side encryption configuration in the same module.
# (Matching is per module address because the bucket ID is unknown at plan time.)
s3_modules_with_sse contains m if {
	some r in surviving_resources
	r.type == "aws_s3_bucket_server_side_encryption_configuration"
	m := object.get(r, "module_address", "")
}

deny contains msg if {
	some r in changed_resources
	r.type == "aws_s3_bucket"
	count(as_list(object.get(r.change.after, "server_side_encryption_configuration", []))) == 0
	m := object.get(r, "module_address", "")
	not m in s3_modules_with_sse
	msg := sprintf("Governance Violation: S3 bucket '%v' has no server-side encryption configuration.", [r.address])
}

# SQS: SSE-SQS (managed) or a KMS key. SNS: a KMS key (there is no managed option).
deny contains msg if {
	some r in changed_resources
	r.type == "aws_sqs_queue"
	object.get(r.change.after, "sqs_managed_sse_enabled", false) != true
	not attr_is_set(r, "kms_master_key_id")
	msg := sprintf("Governance Violation: SQS queue '%v' must enable sqs_managed_sse_enabled or set kms_master_key_id.", [r.address])
}

deny contains msg if {
	some r in changed_resources
	r.type == "aws_sns_topic"
	not attr_is_set(r, "kms_master_key_id")
	msg := sprintf("Governance Violation: SNS topic '%v' must set kms_master_key_id.", [r.address])
}
