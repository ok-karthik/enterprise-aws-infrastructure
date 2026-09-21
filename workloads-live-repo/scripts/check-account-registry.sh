#!/usr/bin/env bash
set -euo pipefail

# Checks every account.hcl in both live repos against the account registry
# (foundation-live-repo/_config/accounts.hcl). No AWS access needed. Fails if:
#   - the folder name is not the account_name,
#   - the account is not in the registry, or its ID / OU / env differ from the registry,
#   - env.hcl in the same folder has a different env than account.hcl.
# In a real company the workloads repo would read the registry from a pinned foundation release.

cd "$(git rev-parse --show-toplevel)"

REGISTRY="foundation-live-repo/_config/accounts.hcl"
[[ -f "$REGISTRY" ]] || { echo "❌ Registry not found: $REGISTRY" >&2; exit 1; }

# One line per registry account: "<name> <id> <ou> <env>"
registry=$(python3 -c '
import re, sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
for match in re.finditer(r"^    ([A-Za-z0-9_-]+) = \{\n(.*?)^    \}", text, re.M | re.S):
    name, body = match.groups()
    fields = {}
    for line in body.splitlines():
        m = re.match(r"^\s+(\w+)\s*=\s*(?:\"([^\"]*)\"|([^\s#]+))", line)
        if m:
            fields[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3)
    print(name, fields.get("id", ""), fields.get("ou", ""), fields.get("env", ""))
' "$REGISTRY")
[[ -n "$registry" ]] || { echo "❌ No accounts found in $REGISTRY" >&2; exit 1; }

# hcl_value <file> <key>: the first quoted value of `key = "value"`.
hcl_value() {
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1
}

status=0
fail() { echo "❌ $1" >&2; status=1; }

while IFS= read -r file; do
  dir=$(dirname "$file")
  name=$(hcl_value "$file" account_name)
  id=$(hcl_value "$file" aws_account_id)
  ou=$(hcl_value "$file" ou)
  env=$(hcl_value "$file" env)

  if [[ -z "$name" || -z "$id" || -z "$ou" || -z "$env" ]]; then
    fail "$file must set aws_account_id, account_name, ou and env"
    continue
  fi
  [[ "$(basename "$dir")" == "$name" ]] || fail "$file: folder '$(basename "$dir")' is not the account_name '$name'"

  entry=$(grep -E "^${name} " <<<"$registry" || true)
  if [[ -z "$entry" ]]; then
    fail "$file: account '$name' is not in $REGISTRY"
    continue
  fi
  read -r _ reg_id reg_ou reg_env <<<"$entry"
  [[ "$id" == "$reg_id" ]] || fail "$file: aws_account_id $id differs from the registry ($reg_id)"
  [[ "$ou" == "$reg_ou" ]] || fail "$file: ou '$ou' differs from the registry ('$reg_ou')"
  [[ "$env" == "$reg_env" ]] || fail "$file: env '$env' differs from the registry ('$reg_env')"

  if [[ -f "$dir/env.hcl" ]]; then
    env_hcl=$(hcl_value "$dir/env.hcl" env)
    [[ "$env_hcl" == "$env" ]] || fail "$dir/env.hcl: env '$env_hcl' differs from account.hcl ('$env')"
  fi
done < <(find foundation-live-repo workloads-live-repo -name account.hcl -not -path "*/.terragrunt-cache/*")

[[ $status -eq 0 ]] && echo "✅ Every account.hcl matches the registry."
exit $status
