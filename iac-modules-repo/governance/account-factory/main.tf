# Account factory: creates and places the member accounts listed in the account registry.
# Applied from the management account only, by the owner. Accounts are never closed by Terraform:
# prevent_destroy is on, and close_on_deletion is off.

resource "aws_organizations_account" "this" {
  for_each = var.accounts

  name      = each.key
  email     = each.value.email
  parent_id = var.ou_ids[each.value.ou]

  role_name                  = var.role_name
  iam_user_access_to_billing = "ALLOW"
  close_on_deletion          = false

  tags = merge(
    {
      Service   = "governance-account-factory"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )

  lifecycle {
    prevent_destroy = true

    # The provider cannot read these back from an existing (or imported) account, so they always
    # show as a diff. Changing them later is done in AWS, not here.
    ignore_changes = [role_name, iam_user_access_to_billing]

  }
}
