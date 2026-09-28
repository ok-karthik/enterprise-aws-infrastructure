locals {
  # Must match this account's entry in foundation-live-repo/_config/accounts.hcl
  # (workloads-live-repo/scripts/check-account-registry.sh enforces it).
  aws_account_id = "000000000006" # TODO(owner): real account ID (registry placeholder). Until then no stack can run here
  # IAM account alias: globally unique across AWS, lowercase. TODO(owner): change it if it is taken.
  account_alias = "ok-karthik-workloads-prod"
  account_name  = "workloads-prod"
  ou            = "Prod"
  env           = "prod" # dev | staging | prod | global

  # Required by the Owner / DataClassification tag policy (root.hcl default_tags).
  owner               = "platform-team" # TODO(owner): real owning team
  data_classification = "confidential"  # TODO(owner): confirm (public | internal | confidential)
}
