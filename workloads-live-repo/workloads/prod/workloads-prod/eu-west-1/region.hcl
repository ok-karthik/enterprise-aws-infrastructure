locals {
  # Secondary (DR) region. Must equal secondary_region in foundation-live-repo/_config/regions.hcl:
  # smoke-test.sh checks it is in that registry. Kept a literal because the smoke test reads it with grep.
  aws_region = "eu-west-1"
}
