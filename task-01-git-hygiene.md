# Task 01 — Git hygiene

## Goal

Put **`05-cicd/`** under git (its own repo, not the whole `iac-learning` tree) with a correct `.gitignore` BEFORE the first commit. Learn exactly what Terraform files belong in version control and what must never be committed.

**Cost: $0** — local only.

## Learning outcomes

- Know what Terraform artifacts to commit vs ignore (and why leaking state/secrets is the #1 IaC mistake)
- Understand why `.terraform.lock.hcl` IS committed but `.terraform/` is not
- Set up the repo CI will run against

---

## Background questions (answer before coding)

1. Why must `terraform.tfstate` never be committed to git? (two reasons — what does state contain, and what breaks with concurrent edits?)

2. What is in `.terraform/`? Why is it safe to delete and regenerate, hence ignored?

3. `.terraform.lock.hcl` — commit it or ignore it? Why?

4. A `*.tfvars` file may hold secrets. Should you blanket-ignore all tfvars, or is there nuance?

---

## Your task

Write `.gitignore` at the `05-cicd/` root (= repo root; hints — figure out the entries):

- ignore: local state (`*.tfstate`, `*.tfstate.*`), the `.terraform/` dir, crash logs (`crash.log`), any `*.tfvars` holding secrets, `.terraformrc`/`terraform.rc`
- DO commit: all `.tf` files, `.terraform.lock.hcl`, `.github/` workflows, task sheets
- reference: github.com/github/gitignore → `Terraform.gitignore`

Then:

```bash
cd 05-cicd   # this dir is the repo root
git init
git add .gitignore
git status          # confirm NO .tfstate or .terraform/ staged anywhere
git add .
git commit -m "init: terraform learning repo"
```

---

## Verify

```bash
git status --ignored        # .terraform/ and *.tfstate show under "Ignored files"
git ls-files | grep -E "tfstate|\.terraform/"   # MUST return nothing
```

If a state file shows in `git ls-files`, stop and fix `.gitignore` before pushing.

---

## Reflection (answer after coding)

1. You already ran `apply` in Phase 3 — is there a `terraform.tfstate` locally? If so, why is it safe now that remote backend is active?

2. If you accidentally committed `terraform.tfstate` once and later added it to `.gitignore`, is it gone from history? What would you actually need to do?

3. Why commit `.terraform.lock.hcl` but not the `.terraform/` directory — what's the difference in what they hold?
