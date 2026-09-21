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
| `PlanRole` | `github-actions-plan` | `ReadOnlyAccess`; on the state bucket: read state, write/delete `*.tflock` only. Trusts `pull_request` and `refs/heads/main` |
| `ApplyRole` | `github-actions-apply` | `AdministratorAccess` **with** the boundary. Trusts exactly one GitHub Environment (`management` here) |

Tags come from the stack, not the template: `Project`, `ManagedBy=CloudFormation`, `Owner`, `DataClassification` (read from `infrastructure-live/_global/account.hcl`). There are no `Export`s: an export locks the exported resource against changes.

## Deploy it (owner only)

Use an SSO profile for the management account. **Never the default profile.**

```bash
aws sso login --profile <management-admin-profile>
AWS_PROFILE=<management-admin-profile> ./infrastructure-bootstrap/bootstrap.sh
```

The script:

1. **Preflight.** It reads the expected account from `infrastructure-live/_global/account.hcl` and refuses to continue unless your credentials belong to it (no credentials or the wrong account: exit 1, nothing changed).
2. Makes sure the AWS Organization exists (all features; asks before creating one) and that StackSets trusted access is enabled.
3. Creates a **change set**, shows it, and asks before executing it. `--yes` skips the prompts. "No changes" counts as success.
4. Enables termination protection, sets the stack policy, prints the outputs and the GitHub wiring.

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
  --template-body file://infrastructure-bootstrap/cloudformation/account-bootstrap.yaml
aws cloudformation deploy \
  --stack-name platform-bootstrap \
  --template-file infrastructure-bootstrap/cloudformation/account-bootstrap.yaml \
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
  --stack-policy-body file://infrastructure-bootstrap/cloudformation/stack-policy.json
aws cloudformation describe-stacks --stack-name platform-bootstrap --query 'Stacks[0].Outputs'
```

</details>

## Wire GitHub to the roles

1. Create the **`management`** GitHub Environment and add yourself as a required reviewer (Settings → Environments). The apply role only trusts jobs running in it.
2. Repository variables (Settings → Secrets and variables → Actions → **Variables**): `AWS_REGION`, and `AWS_DEV_PLAN_ROLE_ARN` / `AWS_PROD_PLAN_ROLE_ARN` set to the management **plan** role. Plans are read-only, so they can stay pointed at management until `workloads-dev` exists.
3. **Leave `AWS_DEV_APPLY_ROLE_ARN` / `AWS_PROD_APPLY_ROLE_ARN` unset.** The management apply role trusts only `environment:management`, so the dev/prod apply jobs cannot deploy workloads into the management account. That is intended. CI for the org stack (`_global`) comes with PLAN 2.6.

The script prints the exact `gh` commands. Details of the pipeline are in [`docs/CICD.md`](../docs/CICD.md).

## Changing the template later

Edit `cloudformation/account-bootstrap.yaml`, then run `bootstrap.sh` again. It creates an **update** change set, shows you exactly what will change (and whether anything is replaced), and asks before executing. Never edit the stack in the console: the next run would show it as drift. The stack policy blocks replacing or deleting the state bucket, the OIDC provider and the boundary; if you really must, lift the policy for one update on purpose.

## Gotchas

- **One OIDC provider per account.** An account can have only one provider for `token.actions.githubusercontent.com`, so the stack fails if one already exists. Delete it (if nothing uses it) or import it into the stack first.
- **Retained, not deletable.** The bucket is `Retain`, and the bucket, OIDC provider and boundary are protected by the stack policy; the stack also has termination protection. If the stack is ever deleted and recreated, creation fails on the bucket name because the old bucket still exists: import that bucket into the new stack by hand.
- **`environment:dev` can apply to any NonProd account.** Every NonProd account trusts the same `dev` GitHub Environment, so a job in `dev` can apply to all of them. Per-account Environments come with PLAN 2.6.
- **`ROLLBACK_COMPLETE`** (a failed first deploy): delete that stack and run the script again. Nothing was created.
- Checks that run without AWS access: `cfn-lint` and `checkov -f infrastructure-bootstrap/cloudformation/account-bootstrap.yaml` (also in pre-commit and CI).
