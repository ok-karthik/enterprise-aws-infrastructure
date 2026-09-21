# 🚀 Day-0 Bootstrap (CloudFormation)

Everything Terraform needs before it can run: a state bucket, the GitHub OIDC trust, and the two IAM roles CI assumes. It is one CloudFormation template, deployed once by a human into the **management account** (`954171757349`). Member accounts get the same template through StackSets (PLAN 2.0b).

Why CloudFormation and not Terraform/Terragrunt: Terraform cannot create the bucket that holds its own state, and Terragrunt's `--backend-bootstrap` creates that bucket *outside any state*, so nobody could plan or drift-check its settings. CloudFormation keeps its own state inside AWS, and StackSets deploy it to every new account automatically. Organizations, OUs, SCPs and everything after Day-0 stay in Terraform.

## What the stack (`platform-bootstrap`) creates

Template: [`cloudformation/account-bootstrap.yaml`](cloudformation/account-bootstrap.yaml). Stack policy: [`cloudformation/stack-policy.json`](cloudformation/stack-policy.json).

| Resource | What | Notes |
|---|---|---|
| `StateBucket` | `tg-state-<account-id>-<region>` | Versioned, SSE-S3, all Block Public Access on, `BucketOwnerEnforced`, old versions expire after 90 days. `Retain` on delete. TLS 1.2+ only (bucket policy). KMS and access logging come with PLAN 2.2 |
| `GitHubOidcProvider` | IAM OIDC provider for `token.actions.githubusercontent.com` | No thumbprint needed |
| `ApplyBoundary` | `github-actions-apply-boundary` | Caps the apply role. Denies Identity Center, CloudTrail changes, organization destruction, edits to the CI roles/OIDC provider/boundary, changes to the state bucket's settings and to this stack. Denies `organizations:*` / `account:*` too, except where `AllowOrganizationsAdmin=true` (management) |
| `PlanRole` | `github-actions-plan` | `ReadOnlyAccess`; on the state bucket: read state, write/delete `*.tflock` only. Trusts any job of this repo (`repo:<repo>:*`, widened by hand from `pull_request` + `main`; read-only, but it can read every state file, so narrow it if you add collaborators) |
| `ApplyRole` | `github-actions-apply` | `AdministratorAccess` **with** the boundary. Trusts exactly one GitHub Environment (`management` here) |

Tags come from the stack, not the template: `Project`, `ManagedBy=CloudFormation`, `Owner`, `DataClassification` (read from `foundation-live-repo/management/account.hcl`). There are no `Export`s: an export locks the exported resource against changes.

## Deploy it (owner only)

You can deploy the bootstrap using any of the following three methods. If you are already logged into the AWS Console in your browser and want a **100% keyless, zero-setup** deployment, **Option 1** is recommended.

### Option 1: AWS Web Console (100% Keyless — Recommended for zero-setup)

No local AWS CLI profiles or access keys needed.

1. **Enable StackSets in Organizations (One-time, for Phase 2)**: In the AWS Console, go to **AWS Organizations** → **Services** (left sidebar menu) → click **AWS CloudFormation StackSets** → click **Enable trusted access**. *(Note: Your Day-0 `platform-bootstrap` stack is a standard CloudFormation stack, so it will deploy even if this is enabled later, but enabling it now prepares your org for member account StackSets).*
2. Go to **AWS CloudFormation** in region `eu-central-1` (Frankfurt).
3. Click **Create stack** → **With new resources (standard)**.
4. Under *Template source*, choose **Upload a template file** and select [`cloudformation/account-bootstrap.yaml`](cloudformation/account-bootstrap.yaml).
5. Specify stack details:
   - **Stack name**: `platform-bootstrap`
   - **GitHubRepo**: `ok-karthik/enterprise-aws-infrastructure`
   - **GitHubEnvironment**: `management`
   - **AllowOrganizationsAdmin**: `true`
6. Configure stack options:
   - Add Tags:
     - `Project` = `enterprise-aws-platform`
     - `ManagedBy` = `CloudFormation`
     - `Owner` = `platform-team`
     - `DataClassification` = `internal`
   - Enable **Stack failure options**: *Roll back all stack resources*.
7. Review & Capabilities:
   - Scroll to the bottom and check:
     `[✔] I acknowledge that AWS CloudFormation might create IAM resources with custom names.`
   - Click **Submit**.
8. After creation reaches `CREATE_COMPLETE`:
   - Click **Stack actions** → **Edit termination protection** → **Enable**.

---

### Option 2: Guided Script via CLI / SSO (`bootstrap.sh`)

If you have AWS CLI configured locally with an SSO profile or exported session credentials:

```bash
# If using AWS IAM Identity Center (SSO):
aws sso login --profile <management-admin-profile>
AWS_PROFILE=<management-admin-profile> ./foundation-live-repo/_bootstrap/bootstrap.sh

# Or if using exported temporary session credentials:
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_DEFAULT_REGION="eu-central-1"
./foundation-live-repo/_bootstrap/bootstrap.sh
```

The script:
1. **Preflight.** Reads the expected account from `foundation-live-repo/management/account.hcl` (`954171757349`) and aborts if your credentials belong to a different account (safeguards against running in the wrong browser/profile session).
2. Verifies the AWS Organization exists and enables StackSets trusted access (`aws cloudformation activate-organizations-access`).
3. Creates a **change set**, renders an ASCII preview of resources to create, and prompts for confirmation (`--yes` skips).
4. Deploys the stack, turns on termination protection, applies [`cloudformation/stack-policy.json`](cloudformation/stack-policy.json), and prints the GitHub role ARNs.

---

### Option 3: AWS CloudShell (Zero-Setup CLI)

If you prefer the CLI but don't want to configure local terminal profiles:
1. Open **CloudShell** directly in your AWS Management Account web console (the `[>_]` terminal icon in the top navigation bar).
2. Clone or download the repository files:
   ```bash
   git clone https://github.com/ok-karthik/enterprise-aws-infrastructure.git
   cd enterprise-aws-infrastructure
   ./foundation-live-repo/_bootstrap/bootstrap.sh
   ```
*(CloudShell runs with pre-authenticated session credentials for the active console user, requiring zero static keys).*

It never touches GitHub. Do the printed steps yourself.

<details>
<summary>The same steps by hand</summary>

```bash
export AWS_PROFILE=<management-admin-profile> AWS_REGION=eu-central-1
# 1. Preflight: must print 954171757349
aws sts get-caller-identity --query Account --output text

# 2. Organization (all features) + StackSets trusted access. Safe to run again.
aws organizations describe-organization >/dev/null 2>&1 \
  || aws organizations create-organization --feature-set ALL
aws cloudformation activate-organizations-access
aws cloudformation describe-organizations-access          # expect "Status": "ENABLED"

# 3. Deploy through a reviewed change set
aws cloudformation validate-template \
  --template-body file://foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml
aws cloudformation deploy \
  --stack-name platform-bootstrap \
  --template-file foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml \
  --parameter-overrides GitHubEnvironment=management AllowOrganizationsAdmin=true \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags Project=enterprise-aws-platform ManagedBy=CloudFormation Owner=platform-team DataClassification=internal \
  --no-execute-changeset
aws cloudformation describe-change-set --stack-name platform-bootstrap --change-set-name <name printed above>
aws cloudformation execute-change-set  --stack-name platform-bootstrap --change-set-name <name>
aws cloudformation wait stack-create-complete --stack-name platform-bootstrap   # stack-update-complete on later runs

# 4. Lock it down and read the outputs
aws cloudformation update-termination-protection --enable-termination-protection --stack-name platform-bootstrap
aws cloudformation set-stack-policy --stack-name platform-bootstrap \
  --stack-policy-body file://foundation-live-repo/_bootstrap/cloudformation/stack-policy.json
aws cloudformation describe-stacks --stack-name platform-bootstrap --query 'Stacks[0].Outputs'
```

</details>

## Wire GitHub to the roles

Once the CloudFormation stack is deployed, wire GitHub Actions to the created roles using either the GitHub CLI (`gh`) or the GitHub Web UI:

### Via GitHub CLI (`gh`):

```bash
# 1. Create the management environment (add yourself as required reviewer in the UI)
gh api -X PUT repos/ok-karthik/enterprise-aws-infrastructure/environments/management

# 2. The only repository variable. There are no per-environment role variables: every CI job builds its
#    role ARN from the account id in foundation-live-repo/_config/accounts.hcl.
gh variable set AWS_REGION --body "eu-central-1"
```

### Via GitHub Web Console:

1. **GitHub Environment**: Go to **Settings** → **Environments** → click **New environment** → name it `management`. Under **Environment protection rules**, check **Required reviewers** and add yourself as a reviewer. Create `dev`, `prod` (with required reviewers) and `core` the same way when their accounts exist.
2. **Repository Variable**: Go to **Settings** → **Secrets and variables** → **Actions** → **Variables** tab (not Secrets): `AWS_REGION` = `eu-central-1`.

> [!IMPORTANT]
> The old `AWS_DEV_PLAN_ROLE_ARN`, `AWS_PROD_PLAN_ROLE_ARN`, `AWS_DEV_APPLY_ROLE_ARN` and `AWS_PROD_APPLY_ROLE_ARN` variables are no longer read and can be deleted. The pipeline runs an account only once the registry says `ci = true`, the account has a live folder and it has a real (non-placeholder) id. For `management`, set `ci = true` after the organization stack is imported and the placeholders are replaced.

Details of the pipeline architecture are in [`docs/CICD.md`](../docs/CICD.md).

## Changing the template later

Edit `cloudformation/account-bootstrap.yaml`, then run `bootstrap.sh` again. It creates an **update** change set, shows you exactly what will change (and whether anything is replaced), and asks before executing. Never edit the stack in the console: the next run would show it as drift. The stack policy blocks replacing or deleting the state bucket, the OIDC provider and the boundary; if you really must, lift the policy for one update on purpose.

## Gotchas

- **One OIDC provider per account.** An account can have only one provider for `token.actions.githubusercontent.com`, so the stack fails if one already exists. Delete it (if nothing uses it) or import it into the stack first.
- **Retained, not deletable.** The bucket is `Retain`, and the bucket, OIDC provider and boundary are protected by the stack policy; the stack also has termination protection. If the stack is ever deleted and recreated, creation fails on the bucket name because the old bucket still exists: import that bucket into the new stack by hand.
- **`environment:dev` can apply to any NonProd account.** Every NonProd account trusts the same `dev` GitHub Environment, so a job in `dev` can apply to all of them. Per-account Environments come with PLAN 2.6.
- **`ROLLBACK_COMPLETE`** (a failed first deploy): delete that stack and run the script again. Nothing was created.
- Checks that run without AWS access: `cfn-lint` and `checkov -f foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml` (also in pre-commit and CI).
