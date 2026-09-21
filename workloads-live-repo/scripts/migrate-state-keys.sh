#!/usr/bin/env bash
set -euo pipefail

# Prints (and with --execute, runs) the commands that move Terraform state to the keys and buckets
# of the account-first layout (PLAN 2.2). THE OWNER RUNS THIS, never an agent.
#
#   before                                            after
#   _global/<category>/<module>                       foundation-live-repo/management/_global/<category>/<module>
#   dev/<region>/<category>/<module>                  workloads-live-repo/workloads-dev/<region>/<category>/<module>
#   prod/<region>/<category>/<module>                 workloads-live-repo/workloads-prod/<region>/<category>/<module>
#
# The state key is the path below the folder that holds root.hcl, so the account folder is now part
# of it. The bucket also changes for workloads: it is tg-state-<account-id>-<region> and the account
# is a different one than before (the old dev and prod stacks shared the management account).
#
# IF NOTHING WAS EVER APPLIED, there is no state and nothing to move: you do not need to run this.
#
# Usage: migrate-state-keys.sh [--execute] [--old-account-id <id>]
#   default        dry run: only prints the commands
#   --execute      runs them with your current AWS credentials (use an SSO profile with access to BOTH
#                  buckets; if the two accounts need different credentials, run the printed commands
#                  yourself with `aws s3 cp` per profile)
#   --old-account-id  the account that held the old state (default 954171757349, the account dev and
#                  prod used before PLAN 2.2)

EXECUTE=false
OLD_ACCOUNT_ID="954171757349"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) EXECUTE=true ;;
    --old-account-id)
      OLD_ACCOUNT_ID="${2:?--old-account-id needs a value}"
      shift
      ;;
    *)
      echo "Usage: $0 [--execute] [--old-account-id <id>]" >&2
      exit 2
      ;;
  esac
  shift
done

cd "$(git rev-parse --show-toplevel)"

hcl_value() {
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1
}

count=0
skipped=0
placeholders=0
plan_file=$(mktemp)
trap 'rm -f "$plan_file"' EXIT

# Pass 1: work out every move. Nothing is run in this pass.
# Every unit (terragrunt.hcl) of the new layout, with the account folder as first path element.
while IFS= read -r leaf; do
  unit_dir=$(dirname "$leaf")
  repo=${unit_dir%%/*}                 # foundation-live-repo | workloads-live-repo
  below=${unit_dir#*/}                 # <account>/<region|_global>/<category>/<module>
  account=${below%%/*}
  rest=${below#*/}                     # <region|_global>/<category>/<module>
  account_hcl="$repo/$account/account.hcl"
  [[ -f "$account_hcl" ]] || continue

  new_id=$(hcl_value "$account_hcl" aws_account_id)
  segment=${rest%%/*}
  if [[ "$segment" == "_global" ]]; then
    region=$(hcl_value "$repo/$account/_global/region.hcl" aws_region)
  else
    region=$segment
  fi

  # Old key: drop the account folder, and map the old environment folder names.
  case "$account" in
    management)     old_key="$rest" ;;
    workloads-dev)  old_key="dev/$rest" ;;
    workloads-prod) old_key="prod/$rest" ;;
    *)
      echo "# skip $unit_dir: new account, nothing to migrate from"
      skipped=$((skipped + 1))
      continue
      ;;
  esac
  new_key="$account/$rest"
  if [[ "$account" == "management" ]]; then
    old_bucket="tg-state-${new_id}-${region}"   # same account as before
  else
    old_bucket="tg-state-${OLD_ACCOUNT_ID}-${region}"
  fi
  new_bucket="tg-state-${new_id}-${region}"

  if [[ "$new_id" =~ ^0{8,} ]]; then
    placeholders=$((placeholders + 1))
    echo "# $account_hcl still has the placeholder account ID $new_id" >&2
  fi
  echo "s3://${old_bucket}/${old_key}/terraform.tfstate s3://${new_bucket}/${new_key}/terraform.tfstate" >>"$plan_file"
  count=$((count + 1))
done < <(find foundation-live-repo workloads-live-repo -name terragrunt.hcl -not -path "*/_envcommon/*" -not -path "*/.terragrunt-cache/*" | sort)

# Pass 2: print, or run. --execute refuses to start if ANY move is not ready, so it never stops half way.
if [[ "$EXECUTE" == true && "$placeholders" -gt 0 ]]; then
  echo "❌ $placeholders unit(s) point at a placeholder account ID. Fill in the real IDs first. Nothing was run." >&2
  exit 1
fi

while read -r src dst; do
  if [[ "$EXECUTE" == true ]]; then
    echo "+ aws s3 mv $src $dst"
    aws s3 mv "$src" "$dst"
  else
    echo "aws s3 mv $src $dst"
  fi
done <"$plan_file"

if [[ "$EXECUTE" == true ]]; then
  echo "✅ Moved $count state file(s) ($skipped skipped)."
else
  echo "# Dry run: $count command(s) above, $skipped skipped. Nothing was run. Re-run with --execute (or run the commands yourself)."
  echo "# If nothing was ever applied there is no state, and you can ignore all of this."
fi
