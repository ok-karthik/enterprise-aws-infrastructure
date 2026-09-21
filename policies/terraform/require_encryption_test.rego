package main

import rego.v1

enc_input(type, after) := {"resource_changes": [{
	"address": concat(".", [type, "t"]),
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}]}

test_encryption_rds_denied_when_unencrypted if {
	some m in deny with input as enc_input("aws_db_instance", {"storage_encrypted": false})
	contains(m, "storage_encrypted")
}

test_encryption_rds_allowed_when_encrypted if {
	count(deny) == 0 with input as enc_input("aws_db_instance", {"storage_encrypted": true})
}

test_encryption_rds_cluster_denied_when_omitted if {
	count(deny) > 0 with input as enc_input("aws_rds_cluster", {})
}

test_encryption_ebs_volume if {
	count(deny) > 0 with input as enc_input("aws_ebs_volume", {"encrypted": false})
	count(deny) == 0 with input as enc_input("aws_ebs_volume", {"encrypted": true})
}

test_encryption_instance_root_device_denied if {
	count(deny) > 0 with input as enc_input("aws_instance", {"root_block_device": [{"encrypted": false}], "ebs_block_device": []})
	count(deny) == 0 with input as enc_input("aws_instance", {"root_block_device": [{"encrypted": true}], "ebs_block_device": null})
}

test_encryption_launch_template_string_true_allowed if {
	count(deny) == 0 with input as enc_input("aws_launch_template", {"block_device_mappings": [{"device_name": "/dev/xvda", "ebs": [{"encrypted": "true", "volume_size": 20}]}]})
}

test_encryption_launch_template_missing_flag_denied if {
	some m in deny with input as enc_input("aws_launch_template", {"block_device_mappings": [{"device_name": "/dev/xvda", "ebs": [{"volume_size": 20}]}]})
	contains(m, "/dev/xvda")
}

test_encryption_s3_bucket_without_sse_denied if {
	count(deny) > 0 with input as enc_input("aws_s3_bucket", {"bucket": "b"})
}

test_encryption_s3_bucket_with_sse_in_same_module_allowed if {
	count(deny) == 0 with input as {"resource_changes": [
		{"address": "module.b.aws_s3_bucket.this", "module_address": "module.b", "type": "aws_s3_bucket", "change": {"actions": ["create"], "after": {"bucket": "b"}}},
		{"address": "module.b.aws_s3_bucket_server_side_encryption_configuration.this", "module_address": "module.b", "type": "aws_s3_bucket_server_side_encryption_configuration", "change": {"actions": ["create"], "after": {}}},
	]}
}

test_encryption_s3_bucket_tag_update_with_existing_sse_allowed if {
	count(deny) == 0 with input as {"resource_changes": [
		{"address": "module.b.aws_s3_bucket.this", "module_address": "module.b", "type": "aws_s3_bucket", "change": {"actions": ["update"], "after": {"bucket": "b"}}},
		{"address": "module.b.aws_s3_bucket_server_side_encryption_configuration.this", "module_address": "module.b", "type": "aws_s3_bucket_server_side_encryption_configuration", "change": {"actions": ["no-op"], "after": {}}},
	]}
}

test_encryption_s3_sse_in_other_module_does_not_count if {
	count(deny) > 0 with input as {"resource_changes": [
		{"address": "module.a.aws_s3_bucket.this", "module_address": "module.a", "type": "aws_s3_bucket", "change": {"actions": ["create"], "after": {"bucket": "b"}}},
		{"address": "module.b.aws_s3_bucket_server_side_encryption_configuration.this", "module_address": "module.b", "type": "aws_s3_bucket_server_side_encryption_configuration", "change": {"actions": ["create"], "after": {}}},
	]}
}

test_encryption_sqs_managed_sse_allowed if {
	count(deny) == 0 with input as enc_input("aws_sqs_queue", {"sqs_managed_sse_enabled": true, "kms_master_key_id": null})
}

test_encryption_sqs_plain_denied if {
	count(deny) > 0 with input as enc_input("aws_sqs_queue", {"sqs_managed_sse_enabled": false, "kms_master_key_id": null})
}

test_encryption_sqs_kms_key_known_after_apply_allowed if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "aws_sqs_queue.t",
		"type": "aws_sqs_queue",
		"change": {"actions": ["create"], "after": {"name": "q"}, "after_unknown": {"kms_master_key_id": true}},
	}]}
}

test_encryption_sns_needs_kms_key if {
	count(deny) > 0 with input as enc_input("aws_sns_topic", {"name": "t"})
	count(deny) == 0 with input as enc_input("aws_sns_topic", {"name": "t", "kms_master_key_id": "alias/aws/sns"})
}
