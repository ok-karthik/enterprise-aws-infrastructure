# IAM Identity Center (PLAN 3.1 / 3.2): permission sets, groups and account assignments. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/identity/identity-center"
}

# Applied by the owner from the management account, never by CI, in the region where IAM Identity Center
# is enabled (the instance is per organization and region; change the region folder if yours is elsewhere).
#
# TODO(owner): the group names must match your IdP's group display names EXACTLY (SCIM syncs them; with
# manage_groups = false Terraform only reads them and the plan fails if one is missing).
# Who gets what where: OU => group => permission sets. Elevated sets (PlatformEngineer, BreakGlassAdmin)
# are refused in Prod, and BreakGlassAdmin everywhere: they are granted just in time (docs/IDENTITY.md).
inputs = {
  # Assignable accounts come from the registry: the management account and every vended account, but
  # only those with a REAL id (registry placeholders are left out until you fill them in).
  accounts = {
    for name, a in include.root.locals.registry : name => { id = a.id, ou = a.ou }
    if !startswith(a.id, "00000000") && (a.create || name == "management")
  }

  groups = ["developers", "platform-engineers", "security-auditors", "finance"]

  assignments = {
    Root           = { "platform-engineers" = ["ReadOnly"], "finance" = ["Billing"] }
    Security       = { "security-auditors" = ["SecurityAudit"], "platform-engineers" = ["ReadOnly"] }
    Infrastructure = { "platform-engineers" = ["PlatformEngineer"] }
    NonProd        = { "developers" = ["Developer"], "platform-engineers" = ["PlatformEngineer"], "security-auditors" = ["SecurityAudit"] }
    Prod           = { "developers" = ["ReadOnly"], "platform-engineers" = ["ReadOnly"], "security-auditors" = ["SecurityAudit"] }
    Sandbox        = { "developers" = ["Developer"] }
  }

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
