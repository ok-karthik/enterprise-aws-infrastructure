#!/usr/bin/env python3
"""Merge the SARIF files Checkov wrote for each plan into ONE SARIF file with ONE run.

GitHub code scanning accepts a single run per tool and category, so several files (one per tfplan.json) cannot
be uploaded side by side. Duplicate results are dropped: with `directory:` in .checkov.yaml, `checkov -f <plan>`
processes the plan once per configured directory and reports every finding several times.

Usage: merge_sarif.py <input-dir-or-file>... <output.sarif>
Exit code: 0 on success (also when there is nothing to merge, it then writes an empty run), 1 on unreadable input.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def find_sarif_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            files.extend(sorted(p for p in path.rglob("*") if p.is_file()))
        elif path.is_file():
            files.append(path)
    return files


def result_key(result: dict) -> tuple:
    """Two results are the same finding if rule, message and location (file and line) match."""
    locations = result.get("locations") or [{}]
    physical = locations[0].get("physicalLocation", {})
    uri = physical.get("artifactLocation", {}).get("uri", "")
    line = physical.get("region", {}).get("startLine", 0)
    return (result.get("ruleId", ""), uri, line, json.dumps(result.get("message", {}), sort_keys=True))


def merge(documents: list[dict]) -> dict:
    """One document, one run: the first run's tool and metadata, every rule once, every finding once."""
    base_run: dict | None = None
    rules: dict[str, dict] = {}
    results: dict[tuple, dict] = {}
    for doc in documents:
        for run in doc.get("runs", []):
            if base_run is None:
                base_run = {k: v for k, v in run.items() if k not in ("results",)}
            for rule in run.get("tool", {}).get("driver", {}).get("rules", []):
                rules.setdefault(rule.get("id", ""), rule)
            for result in run.get("results", []):
                results.setdefault(result_key(result), result)
    if base_run is None:
        base_run = {"tool": {"driver": {"name": "Checkov"}}}
    base_run.setdefault("tool", {}).setdefault("driver", {})["rules"] = list(rules.values())
    base_run["results"] = list(results.values())
    return {"version": "2.1.0", "$schema": "https://json.schemastore.org/sarif-2.1.0.json", "runs": [base_run]}


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    *inputs, output = argv[1:]
    documents = []
    for path in find_sarif_files([Path(p) for p in inputs]):
        try:
            documents.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"merge_sarif: cannot read {path}: {exc}", file=sys.stderr)
            return 1
    merged = merge(documents)
    Path(output).write_text(json.dumps(merged, indent=2), encoding="utf-8")
    print(f"merge_sarif: {len(documents)} file(s) -> {output}: {len(merged['runs'][0]['results'])} finding(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
