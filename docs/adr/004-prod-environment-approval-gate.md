# 004. Manual approval gate on apply

Status: accepted
Date: 2026-06-13

## Context

ADR 003 makes merge to `main` the apply trigger. A merge alone still applies automatically, with no human checkpoint between merge and a real change to AWS. For infrastructure, an unattended apply on every merge is risky.

## Decision

`apply.yml` runs in a GitHub `prod` environment configured with a required reviewer. The apply job pauses on the environment gate until a reviewer approves, then proceeds.

## Consequences

- A human checkpoint sits between merge and any mutation of AWS.
- Approvals are recorded against the environment, giving an audit trail.
- Apply is no longer fully automated continuous deployment; it requires someone to approve.
- Needs the `prod` environment and its protection rules configured in repo settings (not in code).
