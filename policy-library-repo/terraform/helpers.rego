package main

import rego.v1

# Shared helpers. Every .rego file in this folder is package `main`, so a helper with the same
# name defined in two files would conflict: keep shared ones here and give per-policy helpers
# a policy-specific prefix.

# Resources this plan creates or updates (deletes and no-ops are ignored).
changed_resources contains r if {
	some r in input.resource_changes
	some action in r.change.actions
	action in ["create", "update"]
}

# Resources that will exist after this plan (everything that is not being deleted).
surviving_resources contains r if {
	some r in input.resource_changes
	not "delete" in r.change.actions
}

# Terraform plan JSON uses null for unset lists; treat null / missing as empty.
as_list(x) := x if is_array(x)

as_list(x) := [] if not is_array(x)

# IAM policy statements can be a single object or an array.
as_array(x) := x if is_array(x)

as_array(x) := [x] if not is_array(x)

# An attribute counts as "set" if it has a known non-empty value, or if it is only known after
# apply (e.g. a KMS key ARN created in the same plan).
attr_is_set(r, attr) if {
	v := r.change.after[attr]
	v != null
	v != ""
}

attr_is_set(r, attr) if r.change.after_unknown[attr] == true
