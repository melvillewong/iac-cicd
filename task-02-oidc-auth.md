# Task 02 — OIDC auth (GitHub Actions → AWS)

## Goal

Let GitHub Actions authenticate to AWS with NO stored access keys. Create an OIDC identity provider + an IAM role the workflow assumes via a short-lived token. Bootstrap it locally with your existing IAM user.

**Cost: $0** — IAM OIDC providers, roles, and policies are free.

## Learning outcomes

- Understand OIDC federation: why it replaces long-lived keys in CI
- Write an IAM role trust policy scoped to one repo (the `sub` claim)
- Grant least-privilege permissions (SSM + S3 state access only)

---

## What is OIDC? (read first)

**OIDC = OpenID Connect** — an identity layer on top of OAuth 2.0. It lets one system prove "who I am" to another using a signed, short-lived token (a JWT), instead of a shared password/key.

**The problem it solves here:** the old way = generate an IAM user's access key, paste it into GitHub Secrets. That key is long-lived, leakable, and must be rotated. If the repo or a log leaks it, an attacker has standing AWS access.

**How OIDC fixes it — the flow each workflow run:**

1. GitHub Actions acts as an **OIDC identity provider**. When your workflow runs, GitHub mints a short-lived **JWT** describing this run: which repo, which branch, which environment (the `sub` claim, e.g. `repo:melvillewong/iac-learning:ref:refs/heads/main`).
2. The workflow calls AWS STS: `AssumeRoleWithWebIdentity`, presenting that JWT.
3. AWS checks: (a) do I trust this OIDC provider? (the `aws_iam_openid_connect_provider` you create), and (b) does the role's **trust policy** allow this exact `sub`?
4. If yes, STS returns **temporary credentials** (valid ~1 hour). Workflow uses them, they expire. Nothing stored.

**Key payoff:** no secret to leak or rotate. Access is scoped to a specific repo/branch and auto-expires. Compromising the repo doesn't hand over standing keys.

**Two pieces you create:**
- **OIDC provider** — tells AWS "trust tokens issued by `token.actions.githubusercontent.com`".
- **IAM role** — has a *trust policy* (who may assume it: your repo's `sub`) + a *permissions policy* (what it can do: SSM + S3 state).

---

## Background questions (answer before coding)

1. Why is `AssumeRoleWithWebIdentity` + OIDC safer than storing `AWS_ACCESS_KEY_ID` in GitHub Secrets? (name two concrete risks of the stored-key approach)

2. What is the `sub` claim in the GitHub OIDC token? Why must the role's trust policy pin it to your specific repo (and maybe branch)?

3. What's the difference between a role's **trust policy** (`assume_role_policy`) and its **permissions policy**? Which controls *who can assume*, which controls *what it can do*?

4. Why give the role SSM + S3 (state bucket) permissions only, not `AdministratorAccess`?

---

## Your task

Bootstrap locally with your existing IAM user (it has admin → can create these). Write a `cicd-iam.tf` (or add to `main.tf`), hints:

### OIDC provider
- resource `aws_iam_openid_connect_provider`
- `url = "https://token.actions.githubusercontent.com"`
- `client_id_list = ["sts.amazonaws.com"]`
- `thumbprint_list` — GitHub's cert thumbprint (look up current value in AWS docs / configure-aws-credentials README)

### IAM role
- resource `aws_iam_role`, `assume_role_policy` = trust policy (JSON or `data "aws_iam_policy_document"`):
  - `Principal` = `Federated` → the OIDC provider ARN
  - `Action` = `sts:AssumeRoleWithWebIdentity`
  - `Condition`: `StringEquals` on `...:aud = sts.amazonaws.com`, and `StringLike` on `...:sub = repo:melvillewong/iac-learning:*` (your actual remote repo; tighten to specific branches later)

### Permissions policy
- resource `aws_iam_role_policy` (inline) or `aws_iam_policy` + attachment
- allow: `ssm:GetParameter`, `ssm:PutParameter`, `ssm:DeleteParameter`, `ssm:AddTagsToResource`, `ssm:ListTagsForResource` on your parameter ARN
- allow: `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on the state bucket (so the runner can read/write state)

Then bootstrap:

```bash
terraform init     # uses your S3 backend
terraform apply    # your IAM user creates the OIDC provider + role
terraform output role_arn    # add a role_arn output; you'll need it in task 03
```

---

## Verify

```bash
aws iam list-open-id-connect-providers      # GitHub provider listed
aws iam get-role --role-name <your-role>    # trust policy shows your repo sub
terraform output role_arn
```

---

## Reflection (answer after coding)

1. If a teammate forks your repo and runs a workflow, can their fork assume your role? Why/why not (think about the `sub` condition)?

2. The OIDC role has no access keys at all. How does the runner end up with usable AWS credentials at runtime?

3. Why is this role created by your local IAM user and not by the CI pipeline itself? (chicken-egg — what must exist before the first CI run?)
