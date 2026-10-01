include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/compute/eks.hcl"
  expose = true
}

# Warm-standby DR cluster: the control plane exists, but the node group scales to zero until a failover.
# Scale up by raising min/desired here and merging the PR (see docs/DISASTER_RECOVERY.md, "Regional failover").
inputs = {
  min_size     = 0
  max_size     = 3
  desired_size = 0
}
