# Weekly cost janitor (PLAN 9.5): reports unattached EBS volumes, old snapshots, unassociated Elastic IPs and log groups without retention. Dev only, never prod. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/governance/cost-janitor"
}

# Report-only. Read the first weekly summary in CloudWatch Logs before setting dry_run = false.
inputs = {
  dry_run = true

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
