package main

import rego.v1

sg_input(type, address, after) := {"resource_changes": [{
	"address": address,
	"type": type,
	"change": {"actions": ["create"], "after": after},
}]}

test_open_ingress_ssh_from_world_denied if {
	some m in deny with input as sg_input("aws_security_group", "aws_security_group.bad", {"ingress": [{"from_port": 22, "to_port": 22, "protocol": "tcp", "cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": []}]})
	contains(m, "port 22")
}

test_open_ingress_range_covering_postgres_denied if {
	count(deny) > 0 with input as sg_input("aws_security_group", "aws_security_group.bad", {"ingress": [{"from_port": 5000, "to_port": 6000, "protocol": "tcp", "cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": null}]})
}

test_open_ingress_ipv6_denied if {
	count(deny) > 0 with input as sg_input("aws_security_group_rule", "aws_security_group_rule.bad", {"type": "ingress", "from_port": 3389, "to_port": 3389, "protocol": "tcp", "cidr_blocks": [], "ipv6_cidr_blocks": ["::/0"]})
}

test_open_ingress_all_traffic_denied if {
	count(deny) > 0 with input as sg_input("aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_ingress_rule.bad", {"ip_protocol": "-1", "cidr_ipv4": "0.0.0.0/0"})
}

test_open_ingress_vpc_rule_redis_denied if {
	count(deny) > 0 with input as sg_input("aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_ingress_rule.bad", {"ip_protocol": "tcp", "from_port": 6379, "to_port": 6379, "cidr_ipv4": "0.0.0.0/0"})
}

test_open_ingress_https_from_world_allowed if {
	count(deny) == 0 with input as sg_input("aws_security_group", "aws_security_group.alb", {"ingress": [{"from_port": 443, "to_port": 443, "protocol": "tcp", "cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": []}]})
}

test_open_ingress_ssh_from_private_cidr_allowed if {
	count(deny) == 0 with input as sg_input("aws_security_group", "aws_security_group.ok", {"ingress": [{"from_port": 22, "to_port": 22, "protocol": "tcp", "cidr_blocks": ["10.0.0.0/8"], "ipv6_cidr_blocks": []}]})
}

test_open_ingress_egress_rule_ignored if {
	count(deny) == 0 with input as sg_input("aws_security_group_rule", "aws_security_group_rule.egress", {"type": "egress", "from_port": 0, "to_port": 0, "protocol": "-1", "cidr_blocks": ["0.0.0.0/0"]})
}
