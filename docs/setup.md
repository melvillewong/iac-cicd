# Phase 4 — CI/CD Setup

Wire Terraform into GitHub Actions. Runner authenticates to AWS via OIDC (no stored keys), runs `plan` on PR and `apply` on merge.

**Cost: $0** — manages only an SSM parameter (always free) + reuses your existing S3 state bucket. GitHub Actions free: 2000 min/month private, unlimited public.

---

## Purpose — the GitOps loop

Goal: git is the source of truth for infra. A change is **proposed** in a PR (preview only) and **applied** on merge (gated). No one runs `terraform apply` by hand.

| Trigger | Workflow | Runs | Effect on AWS |
|---|---|---|---|
| open/update PR | `plan.yml` (task 03) | fmt → init → validate → **plan** | none (read-only preview) |
| merge to `main` | `apply.yml` (task 04) | init → **apply** (after env approval) | applies the diff |

The safety gate before AWS is touched (3 cheap checks, NOT a state test):
- `fmt -check` → formatting/style
- `validate` → config internally valid (refs, types); no AWS call, no state
- `plan` → reads remote state from S3, diffs vs real AWS, shows `+/~/-`. The **human reading this output is the review** — it does not test state correctness. (Heavier checks like tflint/checkov/OPA could slot in here later.)

Why the supporting pieces exist:
- **OIDC (task 02)** → runner gets AWS creds with no stored keys. Auth layer, not the loop.
- **remote state (phase 3 prereq)** → fresh runner has no local state; pulls from S3 to know current infra.
- **plan/apply split** → PR = intent (safe), merge = execution (gated). A PR can never mutate AWS.

---

## What this phase manages

| Resource | Why | Cost |
|---|---|---|
| `aws_ssm_parameter` | tiny real resource so `plan`/`apply` show meaningful diffs | $0 (Standard tier) |
| OIDC provider + IAM role | lets GitHub Actions assume an AWS role with no long-lived keys | $0 |
| S3 backend (existing bucket, new key) | runner pulls/pushes state remotely | $0 |

No EC2, no VPC, no NAT. Nothing billable.

---

## Task overview

| Task | Focus | Est. | Watch out |
|---|---|---|---|
| Prereqs | git init, gh repo, main.tf/vars | 30 min | mechanical, hints given |
| 01 | Git hygiene | 20-30 min | NEVER commit `.tfstate`, `.terraform/`, `*.tfvars` with secrets |
| 02 | OIDC auth | 1.5-2 hr | trust policy `sub` must match your repo exactly, else assume-role denied |
| 03 | plan on PR | 1-1.5 hr | runner needs role + state access; plan must not apply |
| 04 | apply on merge | 45-60 min | gate on `main` only + environment approval; never apply from PR |

**Total ~4-5.5 hr (~3-4 sessions).** CI is debug-heavy: tasks 02-03 burn time on the push → wait → red → fix loop (can't test locally). First-time OIDC errors (`sub` mismatch, missing `id-token: write`) are normal, budget extra.

---

## Prereqs (do once, before task 01)

> **Scope: `05-cicd/` is its own git repo** (not the whole `iac-learning` tree). Phase-3 config in `04-aws-basics/` stays local-only; CI doesn't need it because state lives in S3. Remote repo: `melvillewong/iac-cicd` (contains only `05-cicd/` files; keep it consistent in the OIDC `sub` in task 02).

### 1. Git repo

```bash
cd 05-cicd   # this dir is the repo root
git init
# .gitignore added in task 01 BEFORE first commit
```

### 2. GitHub repo

```bash
gh repo create iac-cicd --private --source=. --remote=origin
# or create on github.com and: git remote add origin <url>
```

### 3. OIDC provider + role — bootstrap (task 02 covers in detail)

GitHub's OIDC provider + an IAM role the workflow assumes. Bootstrapped via Terraform locally first (chicken-egg: role must exist before CI can use it), same pattern as the S3 backend bootstrap.

### 4. Write `main.tf` + `variables.tf` (hints, write it yourself)

**`main.tf` — `terraform {}` block** (mirror `04-aws-basics/main.tf`):
- `required_version`, `required_providers` → aws `~> 5.0`
- `backend "s3"`: reuse your existing state bucket, but give this phase its own `key` so state doesn't collide:
  - `key = "05-cicd/terraform.tfstate"`
  - same `region`, `use_lockfile = true`, `encrypt = true`

**`main.tf` — provider + resource:**
- `provider "aws"` → `region = var.region`
- managed resource = `aws_ssm_parameter` (always free, Standard tier). Required args:
  - `name` → e.g. `/iac-learning/app-message`
  - `type = "String"`
  - `value = var.app_message` (wire to a var so changing it shows a plan diff)
- docs: registry.terraform.io → `aws_ssm_parameter`

**`variables.tf`:**

| Variable | Type | Default |
|---|---|---|
| `region` | `string` | `"eu-west-1"` |
| `app_message` | `string` | `"hello from terraform"` |

**Why SSM parameter:** change `value` → `plan` shows in-place update → clean demo for plan-on-PR (task 03). No compute, no cost.

---

## Notes (common confusion)

- **Why OIDC over secrets?** Stored `AWS_ACCESS_KEY_ID` in GitHub secrets = long-lived, leakable, needs rotation. OIDC issues a short-lived token per run, scoped to your repo. No secret to leak.
- **Why does CI need remote state?** The runner is a fresh machine each run. Local state would be lost. It pulls state from S3, applies, pushes back. Phase 3's backend is the prereq that makes CI possible.
- **plan vs apply split**: PR shows what *would* change (safe, read-only intent). Merge to `main` actually applies (gated). This is the core GitOps loop.
- **Teardown a self-referential state bucket** (bucket holds its own state): can't `destroy` in place.
  - why: destroy deletes bucket, then tries to write state back → bucket gone → fails
  - why: if versioning enabled, bucket blocks `DeleteBucket` (`BucketNotEmpty`) until all object versions purged
  - fix 1: point backend to local + `terraform init -migrate-state` (pull state S3 → local)
  - fix 2: `terraform destroy` (needs `force_destroy = true` on bucket)
  - migrating back to local first is required
