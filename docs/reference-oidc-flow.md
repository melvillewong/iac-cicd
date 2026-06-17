# Reference — OIDC prereqs: AWS-side vs GitHub-side

Who owns what + what must pre-exist. JWT-exchange detail: see `## What is OIDC?` in [task-02-oidc-auth.md](task-02-oidc-auth.md).

## Pre-exist (AWS) vs supplied (GitHub)

**AWS, defined once (task 02):**
- OIDC provider, trusts GitHub tokens
- IAM role + trust policy, who may assume (`sub`, `aud`)
- permissions policy, what it can do (ssm + s3 state)
- S3 state bucket, backend the runner reads/writes

Complete AWS prereq. SSM param = CI manages it (needn't pre-exist); only the bucket must. No AWS setup after task 02.

**GitHub, supplied at runtime (task 03+):**
- role ARN → `role-to-assume` (`vars.AWS_ROLE_ARN`)
- `permissions: id-token: write` → mints the OIDC JWT (missing = auth fails)
- `aws-region`
- steps: checkout → configure-aws-credentials → setup-terraform → init/plan

## Handshake

```
GitHub mints JWT (needs id-token:write)
  → presents to AWS STS with role ARN
     → AWS checks: trusted provider? trust policy sub/aud match?   (AWS-side)
        → returns temp creds scoped to permissions policy          (AWS-side)
```

AWS = identity + trust + perms + bucket. GitHub = which role + token permission + region.

JWT claims must match the AWS config:
- `iss` (token.actions.githubusercontent.com) ↔ OIDC provider `url`
- `aud` (sts.amazonaws.com) ↔ `client_id_list`
- `sub` (repo:owner/repo:ref) ↔ trust policy `sub` condition

## Who fills the JWT claims (you define NONE in GitHub)

GitHub auto-stamps claims from run context; you configure nothing in the repo.
- `iss` = GitHub (fixed, it's the issuer)
- `sub` = GitHub from context (repo + ref that triggered the run)
- `aud` = `configure-aws-credentials` requests `sts.amazonaws.com` (default)

`id-token: write` → action requests JWT from GitHub → GitHub mints it → action calls `AssumeRoleWithWebIdentity` → AWS validates vs trust policy.

AWS defines EXPECTED (trust policy); GitHub stamps ACTUAL (automatic). The `sub` condition is the security boundary: AWS only accepts tokens whose auto-filled `sub` matches your repo.
