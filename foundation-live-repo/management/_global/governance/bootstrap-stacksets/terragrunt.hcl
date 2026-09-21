include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/governance/bootstrap-stacksets.hcl"
  expose = true
}

# One StackSet per GitHub Environment: the environment sets the apply role's trust subject, and
# auto-deployment can only use the StackSet's own parameters (PLAN 2.0b).
#
# TODO(owner): replace every ou-0000-00000000 with the real OU ID. The module refuses to plan
# while the placeholder is still there. Look them up (read-only) with:
#   aws organizations list-organizational-units-for-parent --parent-id <root-or-parent-id>
# After PLAN 2.3 creates the OUs, these IDs come from the organization module's outputs.
#
# Sandbox and Suspended OUs are deliberately not targeted. Do not move an account between OUs
# that are targeted by different StackSets (its stack would be deleted and re-created, and the
# create fails on the retained state bucket name); accounts must not move between Prod and NonProd.
inputs = {
  stack_sets = {
    bootstrap-nonprod = {
      github_environment      = "dev"
      organizational_unit_ids = ["ou-0000-00000000"] # TODO(owner): Workloads/NonProd OU
    }
    bootstrap-prod = {
      github_environment      = "prod"
      organizational_unit_ids = ["ou-0000-00000000"] # TODO(owner): Workloads/Prod OU
    }
    bootstrap-core = {
      github_environment      = "core"
      organizational_unit_ids = ["ou-0000-00000000"] # TODO(owner): Security OU (add the Infrastructure OU id as a second entry)
    }
  }
}
