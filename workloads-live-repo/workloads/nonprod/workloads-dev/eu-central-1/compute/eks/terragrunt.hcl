include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/compute/eks.hcl"
  expose = true
}

# min_size and desired_size come from env.hcl (min 0, desired 1) so the night schedule is valid.
inputs = {
  max_size = 2
}
