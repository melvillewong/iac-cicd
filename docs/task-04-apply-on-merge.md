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

- push-to-main = reviewed + merged = trusted; apply mutates infra so rides the trusted event
- `pull_request` is untrusted: any PR can carry arbitrary workflow code → apply-on-PR = unreviewed changes to AWS. plan-on-PR is safe (read-only)

1. What does a GitHub **Environment** with required reviewers add on top of branch protection?

- branch protection gates the **merge**; environment gates the **deploy** (pauses the apply job until approved)
- different point: branch protection can't pause a running workflow
- also scopes env secrets/vars to approved deploys

1. `terraform apply` in CI needs `-auto-approve`. Isn't that dangerous? Why is it acceptable *here* but the environment gate still matters?

- `-auto-approve` skips terraform's interactive "yes" (no TTY in CI anyway)
- not blind: human "yes" moved earlier → PR plan review + env approval
- env gate still matters: push-to-main has no pause itself; env restores the runtime checkpoint `-auto-approve` removed

1. Two workflows now read the same state in S3. What stops a plan job and an apply job from corrupting state if they overlap?

- `use_lockfile=true` → S3-native state lock. Both **plan and apply** take it (any refresh locks), not just writes
- jobs serialize: first grabs lock, other waits / errors "state locked" → no corruption

---

## Your task

### 1. Create a GitHub Environment

- repo → Settings → Environments → New environment: `production`
- add yourself as a **required reviewer** (forces manual approval before apply runs)

> Note: CI applies **only the `app/` config** (the SSM param). `bootstrap/` (bucket, OIDC, role) is admin-applied locally, never by this workflow.

### 2. Create `.github/workflows/apply.yml` (hints)

- **trigger**: `on: push: branches: [main]` (optionally `paths: app/**`)
- **job**: `environment: production` (triggers the approval prompt) + `defaults.run.working-directory: app`
- **permissions**: `id-token: write`, `contents: read`
- **steps** (mirror `plan.yml`):
  1. `actions/checkout`
  2. `configure-aws-credentials` → `role-to-assume: ${{ vars.AWS_ROLE_ARN }}`, `aws-region: ${{ vars.AWS_REGION }}`
  3. `setup-terraform`
  4. `terraform init` with the same `-backend-config` flags as plan.yml (bucket/key/region from repo vars + `use_lockfile`/`encrypt`)
  5. `terraform apply -auto-approve`

### 3. Run the loop

Add `apply.yml` to the **same PR** as the plan workflow (don't merge a change before apply exists, else main drifts from AWS). The merge that lands `apply.yml` on main also fires it (push events use the default-branch version).

```bash
gh pr merge <PR> --merge        # merges plan+apply; push-to-main triggers apply.yml
gh run watch                    # apply PAUSES for environment approval → approve in GitHub UI
```

---

## Verify

```bash
# after approval + apply completes:
aws ssm get-parameter --name /iac/app-message --query "Parameter.Value" --output text
# value matches what you set in the merged PR
```

---

## Reflection (answer after coding)

1. Open a PR changing `app_message`. Trace the full path: which workflow runs at PR time, which at merge, where the human gate sits.

- PR opened: `plan.yml` runs → posts plan diff
- merged to `main`: `apply.yml` triggers → pauses for env approval → approved → SSM updated

1. If you skipped the `production` environment, what protection would you lose even with branch protection on `main`?

- branch protection gates merge, not deploy; without env, push-to-main fires apply instantly with no pause
- env approval = runtime checkpoint after merge; self-merge fine for solo, env gate is the real guard

1. The lock: if the apply job is mid-run and someone opens a PR triggering a plan, what does `use_lockfile` do? Does plan take the lock?

- yes, plan takes lock too; apply holds it → plan errors "state locked" → apply finishes → lock released → plan retries

1. You're done with Phase 4. What's the minimal teardown — destroy the SSM parameter but KEEP the OIDC role/provider, or remove everything? What does each choice cost? (hint: all $0, so the real question is cleanliness vs reuse)

- keep role: `terraform destroy` in `app/` only; role reusable later
- remove all: destroy `app/` then `bootstrap/`; rebuild = re-run `bootstrap/` apply locally; CI backend config in `app/main.tf`, no manual setup needed
