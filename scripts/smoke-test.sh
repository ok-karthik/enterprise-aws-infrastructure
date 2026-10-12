#!/bin/bash
set -e

# --- 🚀 Platform Smoke Test (Disaster Recovery Validation) ---
# Validates that the platform code is syntactically correct, follows the account-first layout, and
# (with AWS access) that the Terragrunt dependency graph of one account initialises and validates.
#
# Usage: smoke-test.sh [account-directory]   e.g. iac-live-repo/workloads/nonprod/workloads-dev (default) or
# iac-live-repo/root/management. The graph step needs AWS credentials for that account; every other
# step works offline.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

ACCOUNT_DIR="${1:-iac-live-repo/workloads/nonprod/workloads-dev}"
ACCOUNT_DIR_NAME=$(basename "$ACCOUNT_DIR")

# Always run from the repository root, whatever directory the script is called from.
cd "$(git rev-parse --show-toplevel)"

echo "🧪 Starting Platform Smoke Test..."

# 1. Layout and compliance checks
echo "1. Checking Platform Compliance & Standards..."

# Layout and registry: every account folder is a registry key, every region folder is _global or an allowed region
# (regions.hcl), and every stack is one self-contained terragrunt.hcl (the one-file rule).
./scripts/check-account-registry.sh
echo "✅ Compliance checks passed."

echo -e "\n2. Checking HCL formatting..."
if terraform fmt -check -recursive iac-modules-repo && \
   terraform fmt -check -recursive iac-live-repo && \
   terraform fmt -check -recursive policy-library-repo; then
    echo -e "${GREEN}✅ HCL Formatting is correct.${NC}"
else
    echo -e "${RED}❌ HCL Formatting issues found. Fix with 'terragrunt hcl format'.${NC}"
    exit 1
fi

# 3. Dependency Graph Validation (needs AWS credentials for the account)
echo -e "\n3. Validating Terragrunt dependency graph ($ACCOUNT_DIR_NAME)..."
if [ ! -d "$ACCOUNT_DIR" ]; then
  echo "❌ ERROR: $ACCOUNT_DIR does not exist."
  exit 1
fi
cd "$ACCOUNT_DIR"
# We run init first to ensure local caches are updated with any module changes
terragrunt run --all init --non-interactive --log-format bare
if terragrunt run --all validate --non-interactive --log-format bare; then
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
