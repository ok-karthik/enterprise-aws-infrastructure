package main

import rego.v1

# No security group may open these ports to the internet. 22 SSH, 3389 RDP, 5432 Postgres,
# 3306 MySQL, 6379 Redis, 27017 MongoDB, 9200 Elasticsearch/OpenSearch.
sensitive_ports := {22, 3389, 5432, 3306, 6379, 27017, 9200}

open_cidrs := {"0.0.0.0/0", "::/0"}

# Everything below is normalised into {address, cidrs, from, to, protocol}.
ingress_rules contains rule if {
	some r in changed_resources
	r.type == "aws_security_group"
	some ing in as_list(object.get(r.change.after, "ingress", []))
	rule := {
		"address": r.address,
		"cidrs": array.concat(as_list(object.get(ing, "cidr_blocks", [])), as_list(object.get(ing, "ipv6_cidr_blocks", []))),
		"from": object.get(ing, "from_port", 0),
		"to": object.get(ing, "to_port", 0),
		"protocol": object.get(ing, "protocol", ""),
	}
}

ingress_rules contains rule if {
	some r in changed_resources
	r.type == "aws_security_group_rule"
	r.change.after.type == "ingress"
	rule := {
		"address": r.address,
		"cidrs": array.concat(as_list(object.get(r.change.after, "cidr_blocks", [])), as_list(object.get(r.change.after, "ipv6_cidr_blocks", []))),
		"from": object.get(r.change.after, "from_port", 0),
		"to": object.get(r.change.after, "to_port", 0),
		"protocol": object.get(r.change.after, "protocol", ""),
	}
}

ingress_rules contains rule if {
	some r in changed_resources
	r.type == "aws_vpc_security_group_ingress_rule"
	rule := {
		"address": r.address,
		"cidrs": [c |
			some attr in ["cidr_ipv4", "cidr_ipv6"]
			c := object.get(r.change.after, attr, null)
			c != null
		],
		"from": object.get(r.change.after, "from_port", 0),
		"to": object.get(r.change.after, "to_port", 0),
		"protocol": object.get(r.change.after, "ip_protocol", ""),
	}
}

# Protocol "-1" means all traffic, which covers every port.
ingress_covers_port(rule, _) if sprintf("%v", [rule.protocol]) == "-1"

ingress_covers_port(rule, port) if {
	rule.from <= port
	port <= rule.to
}

deny contains msg if {
	some rule in ingress_rules
	some cidr in rule.cidrs
	cidr in open_cidrs
	some port in sensitive_ports
	ingress_covers_port(rule, port)
	msg := sprintf("Governance Violation: '%v' opens port %v to %v. Restrict the source to a security group or a specific CIDR.", [rule.address, port, cidr])
}
