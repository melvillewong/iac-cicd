# Task 04 — Apply on merge

## Goal

Add a second workflow that runs `terraform apply` ONLY when a PR merges to `main`, gated by a manual environment approval. This completes the GitOps loop: PR plans, merge applies.

**Cost: $0** — applies only the SSM parameter.

## Learning outcomes

- Build the write-side of GitOps: merge = deploy, nothing else applies
- Gate production changes behind a GitHub Environment approval
- See why plan (PR) and apply (main) must be separate workflows

---

## Background questions (answer before coding)

1. Why must `apply` trigger on push-to-`main`, never on `pull_request`? (what could a malicious PR do otherwise?)

2. What does a GitHub **Environment** with required reviewers add on top of branch protection?

3. `terraform apply` in CI needs `-auto-approve`. Isn't that dangerous? Why is it acceptable *here* but the environment gate still matters?

4. Two workflows now read the same state in S3. What stops a plan job and an apply job from corrupting state if they overlap?

---

## Your task

### 1. Create a GitHub Environment
- repo → Settings → Environments → New environment: `production`
- add yourself as a **required reviewer** (forces manual approval before apply runs)

### 2. Create `.github/workflows/apply.yml` (hints)

- **trigger**: `on: push: branches: [main]` (repo root = tf config, no `paths` filter needed)
- **job** `environment: production` (this is what triggers the approval prompt)
- **permissions**: `id-token: write`, `contents: read`
- **steps**:
  1. `actions/checkout`
  2. `configure-aws-credentials` → same `role-to-assume`, `aws-region`
  3. `setup-terraform`
  4. `terraform init`
  5. `terraform apply -auto-approve` (tf files at repo root — no `working-directory` needed)

### 3. Run the loop

```bash
# merge the task-03 PR (or open a new one changing app_message)
gh pr merge --merge
# apply workflow starts, then PAUSES for environment approval
gh run watch        # approve in the GitHub UI when prompted
```

---

## Verify

```bash
# after approval + apply completes:
aws ssm get-parameter --name /iac-learning/app-message --query "Parameter.Value" --output text
# value matches what you set in the merged PR
```

---

## Reflection (answer after coding)

1. Open a PR changing `app_message`. Trace the full path: which workflow runs at PR time, which at merge, where the human gate sits.

2. If you skipped the `production` environment, what protection would you lose even with branch protection on `main`?

3. The lock: if the apply job is mid-run and someone opens a PR triggering a plan, what does `use_lockfile` do? Does plan take the lock?

4. You're done with Phase 4. What's the minimal teardown — destroy the SSM parameter but KEEP the OIDC role/provider, or remove everything? What does each choice cost? (hint: all $0, so the real question is cleanliness vs reuse)
