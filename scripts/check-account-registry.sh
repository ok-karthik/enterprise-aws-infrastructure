#!/usr/bin/env bash
set -euo pipefail

# Checks iac-live-repo against the account registry (iac-live-repo/_config/accounts.hcl) and the one-file rule.
# No AWS access needed. Usage: check-account-registry.sh [root-dir]   (default: the repo root; tests pass a temp tree)
# Fails if:
#   - a top-level folder of iac-live-repo (not starting with "_") is not a registry account,
#   - a folder below an account is neither "_global" nor a region allowed for that account's OU
#     (_config/regions.hcl allowed_regions_by_ou; the management account, OU "Root", may use the primary and secondary region),
#   - a terragrunt.hcl is not exactly <account>/<region>/<stack>/terragrunt.hcl,
#   - a terragrunt.hcl calls read_terragrunt_config or get_env(, or find_in_parent_folders anywhere other than
#     `path = find_in_parent_folders("root.hcl")` (the one-file rule: root.hcl is the only file that looks anything up).
# One output line per failure; exit 1 if there is any.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

python3 - "$ROOT" "$SCRIPT_DIR" <<'PY'
import re
import sys
from pathlib import Path

root, script_dir = Path(sys.argv[1]), sys.argv[2]
sys.path.insert(0, script_dir)
from generate_account_matrix import parse_registry  # noqa: E402

live = root / "iac-live-repo"
registry_file = live / "_config" / "accounts.hcl"
regions_file = live / "_config" / "regions.hcl"
for f in (registry_file, regions_file):
    if not f.is_file():
        print(f"❌ not found: {f}", file=sys.stderr)
        sys.exit(1)

registry = parse_registry(registry_file.read_text(encoding="utf-8"))
if not registry:
    print(f"❌ No accounts found in {registry_file}", file=sys.stderr)
    sys.exit(1)

regions_text = regions_file.read_text(encoding="utf-8")
primary = re.search(r'^\s*primary_region\s*=\s*"([^"]+)"', regions_text, re.M)
secondary = re.search(r'^\s*secondary_region\s*=\s*"([^"]+)"', regions_text, re.M)
by_ou: dict[str, list[str]] = {}
block = re.search(r"allowed_regions_by_ou\s*=\s*\{(.*?)^\s*\}", regions_text, re.M | re.S)
if block:
    for m in re.finditer(r'^\s*([\w-]+)\s*=\s*\[(.*?)\]', block.group(1), re.M):
        by_ou[m.group(1)] = re.findall(r'"([^"]+)"', m.group(2))
both = [m.group(1) for m in (primary, secondary) if m]

failures: list[str] = []


def fail(msg: str) -> None:
    failures.append(msg)


def rel(p: Path) -> str:
    return p.relative_to(root).as_posix()


def in_cache(p: Path) -> bool:
    return ".terragrunt-cache" in p.parts


for account_dir in sorted(p for p in live.iterdir() if p.is_dir() and not p.name.startswith("_")):
    name = account_dir.name
    fields = registry.get(name)
    if fields is None:
        fail(f"{rel(account_dir)}: '{name}' is not an account in {rel(registry_file)}")
        continue
    ou = fields.get("ou", "")
    allowed = both if ou == "Root" else by_ou.get(ou, [])
    for region_dir in sorted(p for p in account_dir.iterdir() if p.is_dir() and not in_cache(p)):
        if region_dir.name != "_global" and region_dir.name not in allowed:
            fail(f"{rel(region_dir)}: '{region_dir.name}' is not _global or a region allowed for OU '{ou}' ({', '.join(allowed) or 'none'})")

allowed_include = re.compile(r'^\s*path\s*=\s*find_in_parent_folders\("root\.hcl"\)\s*$')
for leaf in sorted(live.rglob("terragrunt.hcl")):
    if in_cache(leaf):
        continue
    parts = leaf.relative_to(live).parts
    if len(parts) != 4 or parts[0].startswith("_"):
        fail(f"{rel(leaf)}: a stack must be <account>/<region or _global>/<stack>/terragrunt.hcl")
    for n, line in enumerate(leaf.read_text(encoding="utf-8").splitlines(), 1):
        if "read_terragrunt_config" in line:
            fail(f"{rel(leaf)}:{n}: read_terragrunt_config is not allowed in a stack (read it from include.root.locals)")
        if "get_env(" in line:
            fail(f"{rel(leaf)}:{n}: get_env( is not allowed in a stack")
        if "find_in_parent_folders" in line and not allowed_include.match(line):
            fail(f"{rel(leaf)}:{n}: find_in_parent_folders is only allowed as path = find_in_parent_folders(\"root.hcl\")")

for msg in failures:
    print(f"❌ {msg}", file=sys.stderr)
if failures:
    sys.exit(1)
print("✅ iac-live-repo matches the registry and every stack follows the one-file rule.")
PY
