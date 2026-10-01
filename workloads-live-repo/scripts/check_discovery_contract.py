#!/usr/bin/env python3
"""
Validates the Discovery Contract (PLAN 2.9).
Ensures that all parameters declared in docs/discovery-contract.json:
1. Conform to the required schema.
2. Are implemented in the appropriate publisher module (governance/discovery-publisher
   or governance/account-baseline).
3. Do not disappear without versioning deprecation.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CONTRACT_JSON = REPO_ROOT / "docs" / "discovery-contract.json"
PUBLISHER_VARS = REPO_ROOT / "iac-modules-repo" / "governance" / "discovery-publisher" / "variables.tf"
BASELINE_MAIN = REPO_ROOT / "iac-modules-repo" / "governance" / "account-baseline" / "main.tf"

REQUIRED_FIELDS = ("key", "type", "description", "since_version", "owner_module")


def extract_publisher_keys() -> set[str]:
    """Extracts allowed parameter keys from discovery-publisher/variables.tf."""
    content = PUBLISHER_VARS.read_text(encoding="utf-8")
    # Match strings inside contains([ ... ], key)
    match = re.search(r"contains\(\s*\[(.*?)\]\s*,\s*key\)", content, re.DOTALL)
    if not match:
        raise ValueError(f"Could not find contains([...], key) in {PUBLISHER_VARS}")
    raw_list = match.group(1)
    keys = set(re.findall(r'"([^"]+)"', raw_list))
    return keys


def extract_baseline_keys() -> set[str]:
    """Extracts published keys from account-baseline/main.tf."""
    content = BASELINE_MAIN.read_text(encoding="utf-8")
    match = re.search(r"discovery_parameters\s*=\s*var\.publish_ssm_parameters\s*\?\s*\{(.*?)\}\s*:", content, re.DOTALL)
    if not match:
        raise ValueError(f"Could not find discovery_parameters map in {BASELINE_MAIN}")
    raw_map = match.group(1)
    keys = set(re.findall(r'"([^"]+)"\s*=', raw_map))
    return keys


def main() -> int:
    if not CONTRACT_JSON.exists():
        print(f"❌ Contract file not found: {CONTRACT_JSON}", file=sys.stderr)
        return 1

    try:
        with open(CONTRACT_JSON, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as err:
        print(f"❌ Failed to parse JSON in {CONTRACT_JSON}: {err}", file=sys.stderr)
        return 1

    params = data.get("parameters", [])
    if not params:
        print(f"❌ No parameters found in {CONTRACT_JSON}", file=sys.stderr)
        return 1

    publisher_keys = extract_publisher_keys()
    baseline_keys = extract_baseline_keys()
    all_implemented_keys = publisher_keys | baseline_keys

    errors: list[str] = []

    contract_keys: set[str] = set()
    for item in params:
        # 1. Validate required fields
        for field in REQUIRED_FIELDS:
            if field not in item or not str(item[field]).strip():
                errors.append(f"Parameter entry missing required field '{field}': {item}")

        key = item.get("key", "")
        if not key:
            continue

        if key in contract_keys:
            errors.append(f"Duplicate key in discovery-contract.json: {key}")
        contract_keys.add(key)

        # 2. Validate implementation in owner module
        owner = item.get("owner_module", "")
        if "discovery-publisher" in owner:
            if key not in publisher_keys:
                errors.append(f"Key '{key}' claimed by discovery-publisher is missing from {PUBLISHER_VARS}")
        elif "account-baseline" in owner:
            if key not in baseline_keys:
                errors.append(f"Key '{key}' claimed by account-baseline is missing from {BASELINE_MAIN}")
        else:
            errors.append(f"Key '{key}' has unknown owner_module: '{owner}'")

        if key not in all_implemented_keys:
            errors.append(f"Contract key '{key}' is not implemented in any publisher module")

    if errors:
        print("❌ Discovery contract validation errors:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(f"✅ Discovery contract check passed ({len(contract_keys)} parameters verified).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
