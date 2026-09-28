# Facts about the AWS Organization that stacks in several accounts need. One place, so no leaf hardcodes them.
locals {
  # TODO(owner): real organization id (o-xxxxxxxxxx; console > AWS Organizations, or `aws organizations describe-organization`).
  # Modules that take it (security/log-archive, security/org-cloudtrail, governance/data-perimeter,
  # network/ipam, ...) refuse the 0000 placeholder at plan time.
  organization_id = "o-0000000000"

  # TODO(owner): after the first apply of the log-archive leaf, paste its `kms_key_arn` output here. The organization
  # trail (management account) needs the ARN of the log-archive key to encrypt its logs. Refused while it is the placeholder.
  log_archive_kms_key_arn = "arn:aws:kms:eu-central-1:000000000001:key/00000000-0000-0000-0000-000000000000"
}
