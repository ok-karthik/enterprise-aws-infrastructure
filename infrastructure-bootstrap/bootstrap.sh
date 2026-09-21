#!/usr/bin/env bash
set -euo pipefail

# --- Platform Bootstrap (run once, by a human, with admin credentials for the target account) ---
#
# Creates, in order (Terragrunt works out the order from the dependency graph):
#   1. the S3 state bucket for this account (Terragrunt --backend-bootstrap, first run only)
#   2. the GitHub OIDC provider
#   3. the github-actions-apply permissions boundary
#   4. the github-actions-plan and github-actions-apply roles
# and then prints the exact GitHub commands to wire the roles into the pipeline.
#
# Safety:
#   - Refuses to run unless the AWS credentials belong to the account declared in
#     dev/account.hcl. Nothing is created in any other account.
#   - Shows the plan and asks for confirmation before applying. Pass --yes to skip the prompt.
#
# Usage: ./bootstrap.sh [--yes]

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

cd "$(dirname "$0")"

AUTO_APPROVE=false
[[ "${1:-}" == "--yes" ]] && AUTO_APPROVE=true

GITHUB_REPO="${GITHUB_REPOSITORY:-ok-karthik/enterprise-aws-infrastructure}"
SECURITY_DIR="dev/_global/security"

# 1. Preflight: are we in the account this repo says we should be in?
EXPECTED_ACCOUNT=$(sed -n 's/.*aws_account_id *= *"\([0-9]\{12\}\)".*/\1/p' dev/account.hcl)
if [[ -z "$EXPECTED_ACCOUNT" ]]; then
  echo -e "${RED}❌ Could not read aws_account_id from dev/account.hcl${NC}" >&2
  exit 1
fi

ACTUAL_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
  echo -e "${RED}❌ No valid AWS credentials. Log in first (e.g. 'aws sso login') and retry.${NC}" >&2
  exit 1
}

if [[ "$ACTUAL_ACCOUNT" != "$EXPECTED_ACCOUNT" ]]; then
  echo -e "${RED}❌ Wrong AWS account.${NC}" >&2
  echo "   Logged in to : ${ACTUAL_ACCOUNT}" >&2
  echo "   Expected     : ${EXPECTED_ACCOUNT} (dev/account.hcl)" >&2
  echo "   Nothing was changed." >&2
  exit 1
fi

echo -e "${BLUE}⚖️  Platform bootstrap${NC}"
echo "   Account : ${ACTUAL_ACCOUNT}"
echo "   Repo    : ${GITHUB_REPO}"

# 2. Review the plan. --backend-bootstrap creates the state bucket on the first run.
cd dev
echo -e "\n${BLUE}Planning (this creates the state bucket if it does not exist yet)...${NC}"
terragrunt run --all plan --backend-bootstrap --non-interactive

if [[ "$AUTO_APPROVE" != true ]]; then
  read -r -p "Apply the plan above to account ${ACTUAL_ACCOUNT}? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted. Nothing applied."; exit 1; }
fi

# 3. Apply
terragrunt run --all apply --backend-bootstrap --non-interactive
cd ..

# 4. Read back the role ARNs
plan_arn=$(cd "${SECURITY_DIR}/github-actions-plan" && terragrunt output -raw arn)
apply_arn=$(cd "${SECURITY_DIR}/github-actions-apply" && terragrunt output -raw arn)

echo -e "\n${GREEN}✅ Bootstrap complete.${NC}"
cat <<EOF

------------------------------------------------------------
NEXT STEPS: wire GitHub to the roles (nothing below has been run for you)
------------------------------------------------------------
1. Repository variables (Settings → Secrets and variables → Actions → Variables):

   gh variable set AWS_REGION             --repo ${GITHUB_REPO} --body "eu-central-1"
   gh variable set AWS_DEV_PLAN_ROLE_ARN  --repo ${GITHUB_REPO} --body "${plan_arn}"
   gh variable set AWS_PROD_PLAN_ROLE_ARN --repo ${GITHUB_REPO} --body "${plan_arn}"
   gh variable set AWS_DEV_APPLY_ROLE_ARN  --repo ${GITHUB_REPO} --body "${apply_arn}"
   gh variable set AWS_PROD_APPLY_ROLE_ARN --repo ${GITHUB_REPO} --body "${apply_arn}"

   (dev and prod share one AWS account today, so they share the same two roles.)

2. GitHub Environments. The apply role only trusts jobs that run in these:

   gh api -X PUT repos/${GITHUB_REPO}/environments/dev
   gh api -X PUT repos/${GITHUB_REPO}/environments/prod
   # then: Settings → Environments → prod → Required reviewers → add yourself
   # (or use the UI); this is the manual approval gate for production.

3. Open a pull request. The plan job assumes ${plan_arn##*/} and must succeed.
------------------------------------------------------------
EOF
