# Task 03 — Plan on PR

## Goal

Add a GitHub Actions workflow that runs on every pull request: format check, init, validate, and `terraform plan`. The plan is posted so reviewers see what *would* change before merge. No apply happens here.

**Cost: $0** — `plan` makes no changes; reads state + queries AWS only.

## Learning outcomes

- Build the read-side of the GitOps loop: PR shows the diff, nothing mutates
- Wire OIDC auth into a real workflow (`id-token: write` + `configure-aws-credentials`)
- Understand why `fmt`/`validate`/`plan` belong in CI as a safety gate

---

## Background questions (answer before coding)

1. Why run `terraform plan` (not `apply`) on a PR? What does the reviewer gain?

2. The workflow needs `permissions: id-token: write`. What breaks without it? (tie back to OIDC)

3. Why run `terraform fmt -check` and `validate` in CI rather than trusting local runs?

4. The runner is a fresh VM with no state. How does it get the current state to diff against?

---

## Your task

Create `.github/workflows/plan.yml` (hints — fill the details):

- **trigger**: `on: pull_request` (repo root = the tf config, so no `paths` filter needed)
- **permissions** (top level or job): `id-token: write` (OIDC), `contents: read`, `pull-requests: write` (to comment)
- **job steps**:
  1. `actions/checkout`
  2. `aws-actions/configure-aws-credentials` → `role-to-assume: <role_arn from task 02>`, `aws-region: eu-west-1`
  3. `hashicorp/setup-terraform`
  4. `terraform fmt -check`
  5. `terraform init`
  6. `terraform validate`
  7. `terraform plan -no-color` (tf files at repo root — no `working-directory` needed)
  8. (nice-to-have) post the plan output as a PR comment
- store the role ARN as a repo **variable** (`vars.AWS_ROLE_ARN`) or secret, not hardcoded

Then:

```bash
git checkout -b feat/cicd-plan
git add .github/workflows/plan.yml
git commit -m "ci: terraform plan on PR"
git push -u origin feat/cicd-plan
gh pr create --fill
# watch the run
gh run watch
```

---

## Verify

- PR shows the workflow running → green
- `plan` step output lists the SSM parameter as `+ create` (or `~ update` if you changed the value)
- No resources actually created (check: `aws ssm get-parameter --name /iac-learning/app-message` still errors / unchanged until merge)

---

## Reflection (answer after coding)

1. Change `app_message` in a PR. What does the plan show, and what is still true about AWS until you merge?

2. If `configure-aws-credentials` fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity", where do you look — the workflow, the trust policy, or both?

3. Why store the role ARN as a repo variable instead of hardcoding it in the YAML? (it's not secret — so why?)
