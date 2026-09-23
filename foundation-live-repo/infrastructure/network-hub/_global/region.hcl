locals {
  # IPAM is global-scoped (one resource per organization, not per region), so its leaf lives in a
  # region-independent _global folder, matching foundation-live-repo/management/_global's pattern. The AWS
  # region here is only where the IPAM resource itself is created (its operating_regions cover every region
  # it manages, regardless of this one).
  aws_region = "eu-central-1"
}
