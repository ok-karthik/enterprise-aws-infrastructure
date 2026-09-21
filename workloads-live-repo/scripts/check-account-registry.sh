#!/usr/bin/env bash
set -euo pipefail

# Fails if any account.hcl in either live repo uses an account ID that is not in the registry
# (foundation-live-repo/_config/accounts.hcl). No AWS access needed. In a real company the workloads
# repo would read the registry from a pinned foundation release instead of the sibling folder.

cd "$(git rev-parse --show-toplevel)"

REGISTRY="foundation-live-repo/_config/accounts.hcl"
[[ -f "$REGISTRY" ]] || { echo "❌ Registry not found: $REGISTRY" >&2; exit 1; }

registry_ids=$(sed -n 's/^[[:space:]]*id[[:space:]]*=[[:space:]]*"\([0-9]\{12\}\)".*/\1/p' "$REGISTRY")
[[ -n "$registry_ids" ]] || { echo "❌ No account IDs found in $REGISTRY" >&2; exit 1; }

status=0
while IFS= read -r file; do
  id=$(sed -n 's/^[[:space:]]*aws_account_id[[:space:]]*=[[:space:]]*"\([0-9]*\)".*/\1/p' "$file" | head -n 1)
  if [[ -z "$id" ]]; then
    echo "❌ $file has no aws_account_id" >&2
    status=1
  elif ! grep -qx "$id" <<<"$registry_ids"; then
    echo "❌ $file uses account $id, which is not in $REGISTRY" >&2
    status=1
  fi
done < <(find foundation-live-repo workloads-live-repo -name account.hcl -not -path "*/.terragrunt-cache/*")

[[ $status -eq 0 ]] && echo "✅ Every account.hcl uses an account listed in the registry."
exit $status
