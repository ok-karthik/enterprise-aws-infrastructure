#!/usr/bin/env python3
"""Fail if a real AWS account id from iac-live-repo/_config/accounts.local.hcl appears in a tracked file.

The repository is public; the real ids live only in the gitignored accounts.local.hcl. This check reads those ids
and scans every tracked text file for them. When accounts.local.hcl does not exist (CI, a fresh clone) there is
nothing to compare against, so it prints a note and exits 0.

Output never shows a full id: only file:line and the id masked as its first 3 digits + ***.
Usage: check_no_real_ids.py [root-dir]   (default: the repo root; tests pass a temp repo)
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_account_matrix import LOCAL_REGISTRY, REPO_ROOT, parse_registry  # noqa: E402

# Ids that are already public and may appear in tracked files: the management account (the Day-0 bootstrap
# docs and the committed registry name it).
ALLOWED_IDS = {"954171757349"}


def mask(account_id: str) -> str:
    return account_id[:3] + "***"


def real_ids(root: Path) -> set[str]:
    path = root / LOCAL_REGISTRY
    if not path.is_file():
        return set()
    accounts = parse_registry(path.read_text(encoding="utf-8"))
    ids = {f.get("id", "") for f in accounts.values()}
    return {i for i in ids if re.fullmatch(r"\d{12}", i)} - ALLOWED_IDS


def tracked_files(root: Path) -> list[str]:
    out = subprocess.run(["git", "ls-files", "-z"], cwd=root, check=True, capture_output=True).stdout
    return [p for p in out.decode("utf-8").split("\0") if p]


def find_leaks(root: Path, ids: set[str]) -> list[str]:
    pattern = re.compile(r"(?<!\d)(" + "|".join(sorted(ids)) + r")(?!\d)")
    leaks: list[str] = []
    for name in tracked_files(root):
        path = root / name
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue  # binary file
        for number, line in enumerate(text.splitlines(), 1):
            for match in pattern.finditer(line):
                leaks.append(f"{name}:{number}: real account id {mask(match.group(1))}")
    return leaks


def main(argv: list[str] | None = None, root: Path = REPO_ROOT) -> int:
    args = sys.argv[1:] if argv is None else argv
    if args:
        root = Path(args[0])
    ids = real_ids(root)
    if not ids:
        print(f"note: {LOCAL_REGISTRY} not found or has no real ids; nothing to check.")
        return 0
    leaks = find_leaks(root, ids)
    for leak in leaks:
        print(f"❌ {leak}", file=sys.stderr)
    if leaks:
        print(f"{len(leaks)} real account id(s) in tracked files: replace them with a fake id (777777777777).", file=sys.stderr)
        return 1
    print(f"✅ no real account id in tracked files ({len(ids)} ids checked).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
