include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/network/dns.hcl"
  expose = true
}

# DNS for eu-central-1. Apply after the real Workloads OU ARN and log-archive account id are filled in
# (_envcommon/network/dns.hcl). See the module README for the two Checkov skips that need a us-east-1
# follow-up (DNSSEC signing, public-zone query logging), not built by this leaf either.
inputs = {}
