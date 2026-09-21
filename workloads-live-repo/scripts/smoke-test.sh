#!/bin/bash
set -e

# --- 🚀 Platform Smoke Test (Disaster Recovery Validation) ---
# Validates that the platform code is syntactically correct, follows the account-first layout, and
# (with AWS access) that the Terragrunt dependency graph of one account initialises and validates.
#
# Usage: smoke-test.sh [account-folder]     e.g. workloads-dev (default). The graph step needs AWS
# credentials for that account; every other step works offline.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

ACCOUNT_DIR_NAME="${1:-workloads-dev}"

# Always run from the repository root, whatever directory the script is called from.
cd "$(git rev-parse --show-toplevel)"

# Module versions are pinned per account (module_versions in env.hcl), but the pinned tags do
# not exist at the new iac-modules-repo path until every module is released again (PLAN 1.4).
# Until then use the modules from this checkout. Set IAC_MODULES_LOCAL= (empty) to use the pins.
export IAC_MODULES_LOCAL="${IAC_MODULES_LOCAL-1}"

echo "🧪 Starting Platform Smoke Test..."

# 1. Layout and compliance checks
echo "1. Checking Platform Compliance & Standards..."

# Regions come from the region registry, not from a hardcoded list.
REGIONS_HCL="foundation-live-repo/_config/regions.hcl"
allowed_regions=$(sed -nE 's/^[[:space:]]*(primary|secondary)_region[[:space:]]*=[[:space:]]*"([^"]*)".*/\2/p' "$REGIONS_HCL")
if [ -z "$allowed_regions" ]; then
  echo "❌ ERROR: no primary_region / secondary_region found in $REGIONS_HCL."
  exit 1
fi

# Account-first layout: <account>/account.hcl with an env of dev | staging | prod | global.
while IFS= read -r account_file; do
  env_name=$(sed -n 's/^[[:space:]]*env[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$account_file" | head -n 1)
  if [[ ! "$env_name" =~ ^(dev|staging|prod|global)$ ]]; then
    echo "❌ ERROR: env '$env_name' in $account_file is not one of dev|staging|prod|global."
    exit 1
  fi
done < <(find foundation-live-repo workloads-live-repo -name "account.hcl" -not -path "*/.terragrunt-cache/*")

# Every region.hcl must use a region from the registry (and stay EU/US only).
while IFS= read -r region_file; do
  region=$(grep "aws_region" "$region_file" | cut -d'"' -f2)
  if [[ ! "$region" =~ ^(eu-|us-) ]]; then
    echo "❌ ERROR: Region '$region' in $region_file is not supported (EU/US only)."
    exit 1
  fi
  if ! grep -qx "$region" <<<"$allowed_regions"; then
    echo "❌ ERROR: Region '$region' in $region_file is not in $REGIONS_HCL."
    exit 1
  fi
done < <(find foundation-live-repo workloads-live-repo -name "region.hcl" -not -path "*/.terragrunt-cache/*")
echo "✅ Compliance checks passed."

# Every account.hcl must match its registry entry (no AWS access needed).
./workloads-live-repo/scripts/check-account-registry.sh

echo -e "\n2. Checking HCL formatting..."
if terraform fmt -check -recursive iac-modules-repo && \
   terraform fmt -check -recursive foundation-live-repo && \
   terraform fmt -check -recursive workloads-live-repo && \
   terraform fmt -check -recursive policy-library-repo; then
    echo -e "${GREEN}✅ HCL Formatting is correct.${NC}"
else
    echo -e "${RED}❌ HCL Formatting issues found. Fix with 'terragrunt hcl format'.${NC}"
    exit 1
fi

# 3. Dependency Graph Validation (needs AWS credentials for the account)
ACCOUNT_DIR="workloads-live-repo/$ACCOUNT_DIR_NAME"
echo -e "\n3. Validating Terragrunt dependency graph ($ACCOUNT_DIR_NAME)..."
if [ ! -d "$ACCOUNT_DIR" ]; then
  echo "❌ ERROR: $ACCOUNT_DIR does not exist."
  exit 1
fi
cd "$ACCOUNT_DIR"
# We run init first to ensure local caches are updated with any new module versions from Renovate
terragrunt run --all init --non-interactive
if terragrunt run --all validate --non-interactive; then
    echo -e "${GREEN}✅ Dependency graph and variables are valid.${NC}"
else
    echo -e "${RED}❌ Validation failed in $ACCOUNT_DIR_NAME.${NC}"
    exit 1
fi
cd - > /dev/null

# 4. TFLint recursive scan
echo -e "\n4. Running TFLint recursive scan..."
tflint --init
if tflint --recursive --format=compact; then
    echo -e "${GREEN}✅ TFLint passed for all modules.${NC}"
else
    echo -e "${RED}❌ TFLint found issues.${NC}"
    exit 1
fi

echo -e "\n${GREEN}🚀 ALL SMOKE TESTS PASSED! Platform is ready for recovery/deployment.${NC}"
