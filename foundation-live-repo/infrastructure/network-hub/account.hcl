locals {
  # Must match this account's entry in foundation-live-repo/_config/accounts.hcl
  # (workloads-live-repo/scripts/check-account-registry.sh enforces it).
  aws_account_id = "000000000003" # TODO(owner): real account id (registry placeholder). Until then no stack can run here
  # IAM account alias: globally unique across AWS, lowercase. TODO(owner): change it if it is taken.
  account_alias = "ok-karthik-network-hub"
  account_name  = "network-hub"
  ou            = "Infrastructure"
  env           = "global" # dev | staging | prod | global

  # Required by the Owner / DataClassification tag policy (root.hcl default_tags).
  owner               = "platform-team" # TODO(owner): real owning team
  data_classification = "internal"      # network infrastructure, not application data
}
