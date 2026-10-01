package main

import rego.v1

enc_input(type, after) := {"resource_changes": [{
	"address": concat(".", [type, "t"]),
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}]}

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

# The cases below moved to Checkov (PLAN 8.10): Rego no longer denies them.
test_encryption_checkov_owned_resources_are_not_checked_here if {
	count(deny) == 0 with input as enc_input("aws_db_instance", {"storage_encrypted": false})
	count(deny) == 0 with input as enc_input("aws_ebs_volume", {"encrypted": false})
	count(deny) == 0 with input as enc_input("aws_sqs_queue", {"name": "q"})
}
