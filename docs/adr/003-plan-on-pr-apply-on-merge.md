# 003. Plan on PR, apply on merge

Status: accepted
Date: 2026-06-13

## Context

With Git as the source of truth, a change needs a safe preview before it reaches AWS, and an unambiguous trigger for when it is actually applied. Running `terraform apply` by hand defeats both: there is no review artifact and no record of what ran.

## Decision

Two workflows, split by trigger:

- `plan.yml` runs on pull requests. It runs `fmt`, `validate`, and `plan`, then posts the plan summary as a PR comment. It is read-only and never applies.
- `apply.yml` runs on push to `main` (after merge). It runs `apply`.

A pull request can never mutate AWS; only a merge to `main` applies.

## Consequences

- The PR shows intent. The plan output is the review artifact a human reads before approving.
- Apply happens from a single, auditable trigger: merge to `main`.
- Two workflows to maintain instead of one.
- The plan job is hard to test locally; iterating on it means the push, wait, fix CI loop.
