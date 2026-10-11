# Region registry. Per-region leaves and the region SCP read from here.
locals {
  primary_region   = "eu-central-1"
  secondary_region = "eu-west-1"

  # Regions each OU may use. The organization module's region SCP still takes one global
  # allowed_regions list; per-OU lists are wired in with PLAN 4.6.
  allowed_regions_by_ou = {
    Security       = ["eu-central-1"]
    Infrastructure = ["eu-central-1", "eu-west-1"]
    Prod           = ["eu-central-1", "eu-west-1"]
    NonProd        = ["eu-central-1"]
    Sandbox        = ["eu-central-1"]
    Policy-Staging = ["eu-central-1"]
    Suspended      = []
  }
}
