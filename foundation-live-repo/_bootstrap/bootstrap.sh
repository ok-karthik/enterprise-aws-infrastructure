#!/usr/bin/env bash
set -euo pipefail

# --- Day-0 bootstrap of the management account (run once, by a human) ---
#
# Deploys the CloudFormation stack `platform-bootstrap`: the Terraform state bucket, the GitHub
# OIDC provider and the two CI roles. Steps (PLAN 2.0a-2):
#   1. Preflight: are these credentials for the account in foundation-live-repo/_global/account.hcl?
#   2. Make sure the AWS Organization exists (all features) and StackSets trusted access is on.
#   3. Deploy through a reviewed change set (you are shown it and asked before it runs).
#   4. Turn on termination protection, set the stack policy, print the outputs.
# Then it prints the GitHub wiring. It does not touch GitHub.
#
# Use an SSO profile for the management account. The default profile is never used:
#   AWS_PROFILE=<management-admin-profile> ./foundation-live-repo/_bootstrap/bootstrap.sh
#
# Usage: bootstrap.sh [--yes]     (--yes skips the confirmation prompts)

STACK_NAME="platform-bootstrap"
TEMPLATE="foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml"
STACK_POLICY="foundation-live-repo/_bootstrap/cloudformation/stack-policy.json"
ACCOUNT_HCL="foundation-live-repo/_global/account.hcl"
REGION_HCL="foundation-live-repo/_global/region.hcl"
GITHUB_ENVIRONMENT="management"
GITHUB_REPO="${GITHUB_REPOSITORY:-ok-karthik/enterprise-aws-infrastructure}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

AUTO_YES=false
case "${1:-}" in
  "") ;;
  --yes) AUTO_YES=true ;;
  *)
    echo "Usage: $0 [--yes]" >&2
    exit 2
    ;;
esac

fail() {
  echo -e "${RED}❌ $*${NC}" >&2
  exit 1
}

confirm() {
  [[ "$AUTO_YES" == true ]] && return 0
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# Reads `<key> = "<value>"` from an .hcl file (one source of truth for account, owner, region).
hcl_value() {
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1
}

cd "$(dirname "$0")/../.."
export AWS_PAGER=""

EXPECTED_ACCOUNT=$(hcl_value "$ACCOUNT_HCL" aws_account_id)
OWNER=$(hcl_value "$ACCOUNT_HCL" owner)
DATA_CLASSIFICATION=$(hcl_value "$ACCOUNT_HCL" data_classification)
REGION=$(hcl_value "$REGION_HCL" aws_region)

[[ "$EXPECTED_ACCOUNT" =~ ^[0-9]{12}$ ]] || fail "Could not read a 12-digit aws_account_id from ${ACCOUNT_HCL}"
[[ -n "$OWNER" && -n "$DATA_CLASSIFICATION" && -n "$REGION" ]] ||
  fail "Missing owner, data_classification or aws_region in ${ACCOUNT_HCL} / ${REGION_HCL}"

export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"

# 1. Preflight -----------------------------------------------------------------------------
if [[ -z "${AWS_PROFILE:-}" && -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
  fail "Set AWS_PROFILE to your management-account profile (e.g. 'aws sso login --profile <name>'). The default profile is never used."
fi

ACTUAL_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) ||
  fail "No valid AWS credentials. Log in first (e.g. 'aws sso login --profile ${AWS_PROFILE:-<name>}') and retry."

if [[ "$ACTUAL_ACCOUNT" != "$EXPECTED_ACCOUNT" ]]; then
  echo -e "${RED}❌ Wrong AWS account.${NC}" >&2
  echo "   Logged in to : ${ACTUAL_ACCOUNT}" >&2
  echo "   Expected     : ${EXPECTED_ACCOUNT} (${ACCOUNT_HCL})" >&2
  echo "   Nothing was changed." >&2
  exit 1
fi

echo -e "${BLUE}⚖️  Day-0 bootstrap${NC}"
echo "   Account : ${ACTUAL_ACCOUNT}"
echo "   Region  : ${REGION}"
echo "   Stack   : ${STACK_NAME}"
echo "   Repo    : ${GITHUB_REPO} (GitHub Environment: ${GITHUB_ENVIRONMENT})"

# 2. Organization + StackSets trusted access (both safe to run again) -----------------------
echo -e "\n${BLUE}Organization and StackSets trusted access${NC}"
if aws organizations describe-organization >/dev/null 2>&1; then
  echo "   AWS Organization already exists."
else
  confirm "No AWS Organization found. Create one (all features) in ${ACTUAL_ACCOUNT}?" ||
    fail "Aborted. Nothing was changed."
  aws organizations create-organization --feature-set ALL >/dev/null
fi

aws cloudformation activate-organizations-access
ACCESS_STATUS=$(aws cloudformation describe-organizations-access --query Status --output text)
[[ "$ACCESS_STATUS" == "ENABLED" ]] ||
  fail "StackSets trusted access is '${ACCESS_STATUS}', expected ENABLED."
echo "   StackSets trusted access: ENABLED"

# 3. Deploy through a reviewed change set ---------------------------------------------------
echo -e "\n${BLUE}Change set${NC}"
aws cloudformation validate-template --template-body "file://${TEMPLATE}" >/dev/null

STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)

case "$STACK_STATUS" in
  "" | REVIEW_IN_PROGRESS)
    CHANGE_SET_TYPE="CREATE"
    WAIT_COMMAND="stack-create-complete"
    ;;
  CREATE_COMPLETE | UPDATE_COMPLETE | UPDATE_ROLLBACK_COMPLETE | IMPORT_COMPLETE)
    CHANGE_SET_TYPE="UPDATE"
    WAIT_COMMAND="stack-update-complete"
    ;;
  *)
    fail "Stack ${STACK_NAME} is in state ${STACK_STATUS}. Resolve that first: wait for an in-progress stack to finish; a ROLLBACK_COMPLETE stack (failed first deploy, nothing created) must be deleted first (aws cloudformation delete-stack --stack-name ${STACK_NAME}), then run this again."
    ;;
esac
echo "   Existing stack status: ${STACK_STATUS:-none} -> ${CHANGE_SET_TYPE} change set"

CHANGE_SET_NAME="bootstrap-$(date -u +%Y%m%d%H%M%S)"
aws cloudformation create-change-set \
  --stack-name "$STACK_NAME" \
  --change-set-name "$CHANGE_SET_NAME" \
  --change-set-type "$CHANGE_SET_TYPE" \
  --template-body "file://${TEMPLATE}" \
  --parameters \
  "ParameterKey=GitHubRepo,ParameterValue=${GITHUB_REPO}" \
  "ParameterKey=GitHubEnvironment,ParameterValue=${GITHUB_ENVIRONMENT}" \
  "ParameterKey=AllowOrganizationsAdmin,ParameterValue=true" \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags \
  "Key=Project,Value=enterprise-aws-platform" \
  "Key=ManagedBy,Value=CloudFormation" \
  "Key=Owner,Value=${OWNER}" \
  "Key=DataClassification,Value=${DATA_CLASSIFICATION}" >/dev/null

NO_CHANGES=false
if ! aws cloudformation wait change-set-create-complete \
  --stack-name "$STACK_NAME" --change-set-name "$CHANGE_SET_NAME" 2>/dev/null; then
  REASON=$(aws cloudformation describe-change-set --stack-name "$STACK_NAME" \
    --change-set-name "$CHANGE_SET_NAME" --query StatusReason --output text 2>/dev/null || true)
  if [[ "$REASON" == *"didn't contain changes"* || "$REASON" == *"No updates are to be performed"* ]]; then
    NO_CHANGES=true
    aws cloudformation delete-change-set --stack-name "$STACK_NAME" \
      --change-set-name "$CHANGE_SET_NAME" >/dev/null
    echo -e "${GREEN}   No changes: the stack already matches the template.${NC}"
  else
    fail "Creating the change set failed: ${REASON}"
  fi
fi

if [[ "$NO_CHANGES" == false ]]; then
  aws cloudformation describe-change-set --stack-name "$STACK_NAME" \
    --change-set-name "$CHANGE_SET_NAME" \
    --query 'Changes[].ResourceChange.[Action,LogicalResourceId,ResourceType,Replacement]' \
    --output table

  if ! confirm "Execute this change set in account ${ACTUAL_ACCOUNT}?"; then
    aws cloudformation delete-change-set --stack-name "$STACK_NAME" \
      --change-set-name "$CHANGE_SET_NAME" >/dev/null
    # A first-time (CREATE) change set leaves an empty REVIEW_IN_PROGRESS stack behind.
    if [[ "$CHANGE_SET_TYPE" == "CREATE" ]]; then
      aws cloudformation delete-stack --stack-name "$STACK_NAME"
    fi
    fail "Aborted. The change set was discarded and nothing was deployed."
  fi

  aws cloudformation execute-change-set --stack-name "$STACK_NAME" --change-set-name "$CHANGE_SET_NAME"
  echo "   Waiting for ${WAIT_COMMAND}..."
  aws cloudformation wait "$WAIT_COMMAND" --stack-name "$STACK_NAME"
fi

# 4. Lock it down and read the outputs ------------------------------------------------------
echo -e "\n${BLUE}Termination protection, stack policy, outputs${NC}"
aws cloudformation update-termination-protection --enable-termination-protection --stack-name "$STACK_NAME" >/dev/null
aws cloudformation set-stack-policy --stack-name "$STACK_NAME" --stack-policy-body "file://${STACK_POLICY}"

stack_output() {
  aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
STATE_BUCKET=$(stack_output StateBucketName)
PLAN_ROLE_ARN=$(stack_output PlanRoleArn)
APPLY_ROLE_ARN=$(stack_output ApplyRoleArn)

echo -e "\n${GREEN}✅ Bootstrap complete.${NC}"
echo "   State bucket   : ${STATE_BUCKET}"
echo "   Plan role      : ${PLAN_ROLE_ARN}"
echo "   Apply role     : ${APPLY_ROLE_ARN}"

cat <<EOF

------------------------------------------------------------
NEXT STEPS: wire GitHub to the roles (nothing below has been run for you)
------------------------------------------------------------
1. Create the '${GITHUB_ENVIRONMENT}' GitHub Environment and add yourself as a required reviewer
   (Settings -> Environments). The apply role only trusts jobs in this Environment.

   gh api -X PUT repos/${GITHUB_REPO}/environments/${GITHUB_ENVIRONMENT}

2. Repository variables. Plans are read-only, so dev and prod plans can point at this role
   until the workload accounts exist:

   gh variable set AWS_REGION             --repo ${GITHUB_REPO} --body "${REGION}"
   gh variable set AWS_DEV_PLAN_ROLE_ARN  --repo ${GITHUB_REPO} --body "${PLAN_ROLE_ARN}"
   gh variable set AWS_PROD_PLAN_ROLE_ARN --repo ${GITHUB_REPO} --body "${PLAN_ROLE_ARN}"

3. Leave AWS_DEV_APPLY_ROLE_ARN and AWS_PROD_APPLY_ROLE_ARN UNSET. The apply role here trusts
   only environment:${GITHUB_ENVIRONMENT}, so the dev/prod apply jobs cannot deploy workloads into
   the management account. That is intended (CI for the org stack comes with PLAN 2.6).

4. Open a pull request. The plan job assumes github-actions-plan and must succeed.
------------------------------------------------------------
EOF
