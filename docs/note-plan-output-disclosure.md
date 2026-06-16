# Note — plan output disclosure in CI

## Problem

Full plan in a PR comment can leak account IDs/ARNs, resource attributes, sometimes secret values (only masked when marked `sensitive`). A summary comment helps, but the full diff still lands in the **Actions job log**.

## Mental model

**To hide the diff, the plan must run somewhere with its own access control, separate from the repo. GitHub Actions can't, the repo IS the boundary.**

- comments + logs + artifacts = visible to anyone with repo read → all-or-nothing
- can't do "infra sees plan, app devs don't" in pure Actions
- moving the diff (comment → log → artifact) changes *where*, not *who sees it*

## Levels

- **summary in comment, full diff in log** (current): fine for solo/private repo
- **suppress in log**: `terraform plan -out=tfplan > plan.txt 2>&1`, parse summary from file. But artifacts/logs still readable by all repo members → limited gain
- **TACO** (Terraform Cloud / Spacelift / env0): plan runs on their workers, full diff in their RBAC-gated UI, GitHub gets only status + link → "who sees diff" ≠ "who reads repo". The real fix.
  - Atlantis = orchestration/locking, still comments the plan → not concealment

## When to escalate

- solo / single trusted team → summary-in-comment enough
- multiple trust levels, or audit/compliance → TACO with external RBAC

Always mark secret vars/outputs `sensitive = true`.
