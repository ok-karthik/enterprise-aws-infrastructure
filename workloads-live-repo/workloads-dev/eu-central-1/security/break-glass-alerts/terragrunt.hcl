include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/security/break-glass-alerts.hcl"
  expose = true
}

# Tells the account's email address about every BreakGlassAdmin sign-in (docs/BREAK_GLASS.md).
# Verify the rules with a real sign-in during the break-glass drill: the event field names come from
# CloudTrail and are worth confirming once.
inputs = {}
