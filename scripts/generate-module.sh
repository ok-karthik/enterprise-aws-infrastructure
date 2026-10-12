#!/bin/bash
# 🏗️ Terragrunt Stack Generator
# Usage: ./generate-module.sh <category/module> <account> <region>
#   e.g. ./generate-module.sh storage/s3 workloads-dev eu-central-1
# Writes iac-live-repo/<ou folder>/<account>/<region>/<module>/terragrunt.hcl: one self-contained file per stack.

set -e

MODULE_PATH=$1
ACCOUNT=$2
REGION=$3

if [ -z "$MODULE_PATH" ] || [ -z "$ACCOUNT" ] || [ -z "$REGION" ]; then
    echo "❌ Error: module path, account and region are required."
    echo "Usage: $0 <category/module> <account> <region>   (region: an AWS region or _global)"
    exit 1
fi

cd "$(git rev-parse --show-toplevel)"

# The account folder must already exist (it is also a key in iac-live-repo/_config/accounts.hcl).
# If there is none, say so instead of creating a stray folder.
# The folder is <ou folder>/<account> (the OU comes from the registry), so ask generate_account_matrix.py.
if ! ACCOUNT_DIR="$(python3 scripts/generate_account_matrix.py --dir "$ACCOUNT")"; then
    echo "❌ Error: no account folder for '$ACCOUNT'. Add the account to iac-live-repo/_config/accounts.hcl and create iac-live-repo/<ou folder>/$ACCOUNT first."
    exit 1
fi

STACK=$(basename "$MODULE_PATH")
TARGET_DIR="$ACCOUNT_DIR/$REGION/$STACK"

if [ -d "$TARGET_DIR" ]; then
    echo "⚠️ Warning: Stack already exists at $TARGET_DIR"
    exit 0
fi

echo "🚀 Scaffolding new stack: $MODULE_PATH in $ACCOUNT ($REGION)..."

mkdir -p "$TARGET_DIR"

# Generate the one-file stack template
cat <<EOT > "$TARGET_DIR/terragrunt.hcl"
# TODO: one sentence on what this stack is. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "\${get_repo_root()}/iac-modules-repo/$MODULE_PATH"
}

# Account and region values: include.root.locals.{account_name,account_id,env,ou,alias,owner,data_classification,aws_region}
# Registry, regions and organization: include.root.locals.{registry,regions,organization}
inputs = {
  # TODO: inputs
}
EOT

echo "✅ Success! Created $TARGET_DIR/terragrunt.hcl"
echo "👉 Fill in the inputs, then run: scripts/check-account-registry.sh"
