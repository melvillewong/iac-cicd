# 001. OIDC federation over stored AWS keys

Status: accepted
Date: 2026-06-13

## Context

The GitHub Actions runner needs AWS credentials to run Terraform. Two options:

- Store a long-lived IAM access key pair in GitHub Actions secrets.
- Federate with GitHub's OIDC provider and exchange a per-run token for temporary credentials.

Long-lived keys sit in the repo's secret store indefinitely, need manual rotation, and leak permanently if exposed (logs, a compromised action, a fork misconfiguration).

## Decision

Use OIDC. GitHub mints a short-lived OpenID Connect token per run; the workflow calls `sts:AssumeRoleWithWebIdentity` to exchange it for temporary credentials. An IAM role trust policy restricts who may assume the role via the token's `sub` (repo) and `aud` (`sts.amazonaws.com`) claims.

## Consequences

- No static credential to store, rotate, or leak.
- Credentials are short-lived and scoped per run.
- Access is bound to this repository by the trust policy `sub` condition.
- More initial setup: an OIDC provider and trust policy must exist before CI can run (see ADR 002).
- A loose `sub` condition over-grants. The current `repo:owner/iac-cicd:*` allows any ref to assume the role (see README Known limitations).
