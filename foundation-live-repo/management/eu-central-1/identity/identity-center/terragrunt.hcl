include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/identity/identity-center.hcl"
  expose = true
}

# Applied by the owner from the management account, never by CI, in the region where IAM Identity Center
# is enabled (the instance is per organization and region; change the region folder if yours is elsewhere).
#
# TODO(owner): the group names must match your IdP's group display names EXACTLY (SCIM syncs them; with
# manage_groups = false Terraform only reads them and the plan fails if one is missing).
# Who gets what where: OU => group => permission sets. Elevated sets (PlatformEngineer, BreakGlassAdmin)
# are refused in Prod, and BreakGlassAdmin everywhere: they are granted just in time (docs/BREAK_GLASS.md).
inputs = {
  groups = ["developers", "platform-engineers", "security-auditors", "finance"]

  assignments = {
    Root           = { "platform-engineers" = ["ReadOnly"], "finance" = ["Billing"] }
    Security       = { "security-auditors" = ["SecurityAudit"], "platform-engineers" = ["ReadOnly"] }
    Infrastructure = { "platform-engineers" = ["PlatformEngineer"] }
    NonProd        = { "developers" = ["Developer"], "platform-engineers" = ["PlatformEngineer"], "security-auditors" = ["SecurityAudit"] }
    Prod           = { "developers" = ["ReadOnly"], "platform-engineers" = ["ReadOnly"], "security-auditors" = ["SecurityAudit"] }
    Sandbox        = { "developers" = ["Developer"] }
  }
}
