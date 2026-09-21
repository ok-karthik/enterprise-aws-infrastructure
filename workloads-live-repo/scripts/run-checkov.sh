#!/usr/bin/env bash
set -euo pipefail

# The ONE way Checkov is run in this repository: the pre-commit hook, `make checkov` and the CI static-analysis
# step all call this script. It runs `checkov --config-file .checkov.yaml`, and any finding fails it (exit 1).
# .checkov.yaml is the only place settings live (scanned directories, skips, external-module policy). Extra
# arguments are passed through; CI only adds output-format options, which do not change the result.
#
# Usage: run-checkov.sh [extra checkov arguments]

cd "$(git rev-parse --show-toplevel)"

if ! command -v checkov >/dev/null 2>&1; then
  echo "❌ checkov is not installed. Install the pinned version: pip install checkov==<version in .github/docker/Dockerfile>" >&2
  exit 127
fi

# Same version as the toolbox image CI runs in, or "passes locally, fails in CI" comes back.
pinned=$(sed -n 's/^ARG CHECKOV_VERSION=\([0-9][0-9.]*\).*/\1/p' .github/docker/Dockerfile | head -n 1)
actual=$(checkov --version 2>/dev/null | tail -n 1 | tr -d '[:space:]')
if [[ -n "$pinned" && "$actual" != "$pinned" ]]; then
  echo "⚠️  checkov ${actual} is installed, the toolbox image pins ${pinned} (.github/docker/Dockerfile)." >&2
  echo "    Results can differ from CI. Fix: pip install 'checkov==${pinned}'" >&2
fi

exec checkov --config-file .checkov.yaml "$@"
