locals {
  aws_account_id = "954171757349"
  account_name   = "projname" # Your alias

  # Required by the Owner / DataClassification tag policy (root.hcl default_tags).
  owner               = "platform-team" # TODO(owner): real owning team
  data_classification = "internal"      # TODO(owner): confirm (public | internal | confidential)
}
