#!/bin/bash
set -e

# --- 🚀 Platform Smoke Test (Disaster Recovery Validation) ---
# This script validates that the platform code is syntactically correct
# and that the remote state backend is reachable.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Always run from the repository root, whatever directory the script is called from.
cd "$(git rev-parse --show-toplevel)"

# Module versions are pinned per environment (module_versions in env.hcl), but the pinned tags do
# not exist at the new iac-modules-repo path until every module is released again (PLAN 1.4).
# Until then use the modules from this checkout. Set IAC_MODULES_LOCAL= (empty) to use the pins.
export IAC_MODULES_LOCAL="${IAC_MODULES_LOCAL-1}"

echo "🧪 Starting Platform Smoke Test..."

# 1. HCL Syntax Check
echo "1. Checking Platform Compliance & Standards..."
# Verify environment names
for env_dir in workloads-live-repo/dev workloads-live-repo/prod workloads-live-repo/staging; do
  if [ -d "$env_dir" ]; then
    env_name=$(basename "$env_dir")
    if [[ ! "$env_name" =~ ^(dev|prod|staging)$ ]]; then
       echo "❌ ERROR: Unsupported environment folder '$env_name'."
       exit 1
    fi
  fi
done

# Verify regional compliance in region.hcl files (both live repos)
while IFS= read -r region_file; do
  region=$(grep "aws_region" "$region_file" | cut -d'"' -f2)
  if [[ ! "$region" =~ ^(eu-|us-) ]]; then
    echo "❌ ERROR: Region '$region' in $region_file is not supported (EU/US only)."
    exit 1
  fi
done < <(find foundation-live-repo workloads-live-repo -name "region.hcl" -not -path "*/.terragrunt-cache/*")
echo "✅ Compliance checks passed."

echo -e "\n2. Checking HCL formatting..."
if terraform fmt -check -recursive iac-modules-repo && \
   terraform fmt -check -recursive foundation-live-repo && \
   terraform fmt -check -recursive workloads-live-repo && \
   terraform fmt -check -recursive policies; then
    echo -e "${GREEN}✅ HCL Formatting is correct.${NC}"
else
    echo -e "${RED}❌ HCL Formatting issues found. Fix with 'terragrunt hcl format'.${NC}"
    exit 1
fi

# 2. Dependency Graph Validation
echo -e "\n2. Validating Terragrunt dependency graph (Dev)..."
cd workloads-live-repo/dev
# We run init first to ensure local caches are updated with any new module versions from Renovate
terragrunt run --all init --non-interactive
if terragrunt run --all validate --non-interactive; then
    echo -e "${GREEN}✅ Dependency graph and variables are valid.${NC}"
else
    echo -e "${RED}❌ Validation failed in dev stack.${NC}"
    exit 1
fi
cd - > /dev/null

# 3. TFLint recursive scan
echo -e "\n3. Running TFLint recursive scan..."
tflint --init
if tflint --recursive --format=compact; then
    echo -e "${GREEN}✅ TFLint passed for all modules.${NC}"
else
    echo -e "${RED}❌ TFLint found issues.${NC}"
    exit 1
fi

echo -e "\n${GREEN}🚀 ALL SMOKE TESTS PASSED! Platform is ready for recovery/deployment.${NC}"
