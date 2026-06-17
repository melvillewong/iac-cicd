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

- plan = preview diff (read-only); apply = mutate. On a PR you want intent, not change
- reviewer gains: sees exact `+/~/-` before approving → catches bad changes pre-merge

1. The workflow needs `permissions: id-token: write`. What breaks without it? (tie back to OIDC)

- without it, GitHub won't mint the OIDC JWT for the run → `configure-aws-credentials` gets no token → can't assume role → no AWS creds → auth step fails

1. Why run `terraform fmt -check` and `validate` in CI rather than trusting local runs?

- local checks are skippable/forgettable; CI enforces uniformly on every PR, can't bypass
- isolated clean env = objective result, no "works on my machine"

1. The runner is a fresh VM with no state. How does it get the current state to diff against?

- `terraform init` reads the backend config → connects to the S3 bucket → pulls current state. Runner is locally stateless; remote backend is the shared source, plan diffs against it
- CI must supply backend config (`backend.hcl` is gitignored) → pass `-backend-config` flags / repo vars in the workflow

---

## Your task

> Design: state is split into `bootstrap/` (bucket, OIDC, role; admin-applied locally) and `app/` (the SSM param; CI-managed). CI plans **only `app/`** so plan refreshes just the param → least-privilege role suffices. See [lesson-bootstrap-vs-app-state.md](lesson-bootstrap-vs-app-state.md).

Create `.github/workflows/plan.yml` (hints — fill the details):

- **trigger**: `on: pull_request` (optionally `paths: app/**`)
- **job**: `defaults.run.working-directory: app` (CI operates the app config only)
- **permissions** (top level or job): `id-token: write` (OIDC), `contents: read`, `pull-requests: write` (to comment)
- **job steps**:
  1. `actions/checkout`
  2. `aws-actions/configure-aws-credentials` → `role-to-assume: ${{ vars.AWS_ROLE_ARN }}`, `aws-region: ${{ vars.AWS_REGION }}`
  3. `hashicorp/setup-terraform` (keep the wrapper on → exposes plan `stdout` for the comment)
  4. `terraform fmt -check`
  5. `terraform init` with `-backend-config` flags (bucket/key/region from repo vars + `use_lockfile`/`encrypt`; `backend.hcl` is gitignored so CI rebuilds it from vars)
  6. `terraform validate`
  7. `terraform plan -no-color` (`continue-on-error: true` so the comment still posts on failure)
  8. comment a **summary** (resource lines + `Plan:` count), not the full diff → see [note-plan-output-disclosure.md](note-plan-output-disclosure.md)
- store the role ARN + state bucket/key as repo **variables** (`vars.AWS_ROLE_ARN`, `vars.AWS_REGION`, `vars.TF_STATE_BUCKET`, `vars.TF_STATE_KEY`), not hardcoded

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
- the comment shows the summary: `# aws_ssm_parameter.message will be updated in-place` + `Plan: 0 to add, 1 to change, 0 to destroy.`
- No resources actually changed (check: `aws ssm get-parameter --name /iac/app-message --query "Parameter.Value" --output text` still shows the OLD value until merge)

---

## Reflection (answer after coding)

1. Change `app_message` in a PR. What does the plan show, and what is still true about AWS until you merge?

- plan shows `~ update` on the SSM parameter (old value → new value)
- AWS unchanged: plan is read-only, SSM still has old value until merge triggers apply

1. If `configure-aws-credentials` fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity", where do you look — the workflow, the trust policy, or both?

- both: workflow (`id-token: write` missing → no JWT minted), trust policy (`sub` mismatch → STS rejects assume-role)
- check workflow first (cheap), then trust policy `sub` condition (most common mismatch)

1. Why store the role ARN as a repo variable instead of hardcoding it in the YAML? (it's not secret — so why?)

- ARN contains account ID → leaks account info if repo goes public
- one change point: update variable, all workflows pick it up without YAML edits
