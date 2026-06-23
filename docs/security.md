# Security

How this pipeline limits what can go wrong, and where it stops short.

## Credentials

No long-lived AWS credentials exist anywhere in the repo or its secrets. The runner authenticates to AWS through GitHub's OIDC provider and receives temporary STS credentials scoped to a single run (ADR 001).

The trust relationship pins the issuer to GitHub's OIDC provider (`token.actions.githubusercontent.com`). On top of that, the role is assumable only when:

- `aud` is `sts.amazonaws.com`
- `sub` matches this repository (`repo:owner/iac-cicd:*`)

A token minted by any other issuer or repository is rejected.

## IAM permissions

The CI role is scoped to the resources it touches, not `*`:

- `ssm:PutParameter`, `DeleteParameter`, `AddTagsToResource` on the single managed parameter ARN
- `s3:ListBucket` on the state bucket, and `GetObject`/`PutObject`/`DeleteObject` on its objects only

The role cannot reach other parameters, buckets, or services.

## State protection

- Encrypted at rest (`encrypt = true`)
- Versioned, so a bad write can be rolled back
- Locked during apply via native S3 locking (`use_lockfile`), preventing two concurrent runs from corrupting state

State contains resource metadata, so it is never committed. `.gitignore` blocks `*.tfstate`, `.terraform/`, and `*.tfvars`; the real `backend.hcl` is ignored and only `backend.hcl.example` is tracked.

## Pipeline controls

- **Minimal workflow permissions.** `plan.yml` and `apply.yml` request only `id-token: write` and `contents: read` (plan also `pull-requests: write` to post its comment). Nothing broader.
- **PR cannot apply.** Pull request runs are read-only `plan`; only a merge to `main` applies (ADR 003).
- **Approval gate.** Apply runs in a `prod` environment with a required reviewer, so a human approves before any change reaches AWS (ADR 004).

## Known gaps

Accepted limitations and their intended fixes are tracked in the [README Known limitations](../README.md#known-limitations).
