#!/usr/bin/env python3
"""Fail if a Rego rule in policy-library-repo/terraform is not listed in policy-library-repo/POLICIES.md (PLAN 8.10).

helpers.rego and *_test.rego files are not rules and need no entry.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY_DIR = ROOT / "policy-library-repo" / "terraform"
CATALOG = ROOT / "policy-library-repo" / "POLICIES.md"
NOT_RULES = {"helpers.rego"}


def rule_files(policy_dir: Path = POLICY_DIR) -> list[str]:
    return sorted(
        p.name for p in policy_dir.glob("*.rego") if p.name not in NOT_RULES and not p.name.endswith("_test.rego")
    )


def unlisted(catalog_text: str, files: list[str]) -> list[str]:
    return [f for f in files if f"`{f}`" not in catalog_text]


def main() -> int:
    missing = unlisted(CATALOG.read_text(encoding="utf-8"), rule_files())
    if missing:
        for f in missing:
            print(f"::error file=policy-library-repo/POLICIES.md::{f} is not listed in POLICIES.md")
        return 1
    print(f"✅ All {len(rule_files())} Rego rules are listed in policy-library-repo/POLICIES.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
